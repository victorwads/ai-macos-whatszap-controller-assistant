import AVFoundation
import AppKit
import Combine
import Foundation
import Speech

@MainActor
final class AppModel: ObservableObject {
    enum StartupMode {
        case live
        case preview
    }

    @Published var logs: [LogEntry] = []
    @Published var serverCalls: [MCPServerCallEntry] = []
    @Published var accessibilityTrusted = false
    @Published var whatsappRunning = false
    @Published var runtimeDescription = ""
    @Published var conversations: [ConversationSummary] = []
    @Published var selectedConversationId: String?
    @Published var selectedChatState: ChatState?
    @Published var isPolling = false
    @Published var lastRefreshDescription = "Never refreshed"
    @Published var waitingForAccessibilityRelaunch = false
    @Published var messageDraft = ""
    @Published var isSendingMessage = false
    @Published var pollingIntervalSeconds = 3
    @Published var mcpServerHost = "localhost"
    @Published var mcpServerPort = 8080
    @Published var mcpServerPortText = "8080"
    @Published var mcpServerRunning = false
    @Published var mcpServerStatusDescription = "Stopped"
    @Published var conversationAccessMode: ConversationAccessMode = .allowAllExceptDeny
    @Published var denyConversationNames: [String] = []
    @Published var allowConversationNames: [String] = []
    @Published var debugSnapshot: WhatsAppSnapshot?
    @Published var debugNodePath: [Int] = []
    @Published var assistantInstructions = ""
    @Published var pendingClientAskCount = 0
    @Published var microphoneAuthorized = true
    @Published var speechRecognitionAuthorized = true
    @Published var speechSynthesizerSpeaking = false

    let voiceSettings: VoiceSettingsModel
    let handsFreeClientVoiceSettings: HandsFreeClientVoiceSettingsModel
    let inputLockSettings: InputLockSettingsModel
    let mcpSendPrefixSettings: MCPSendPrefixSettingsModel

    let accessibility = AccessibilityService()
    let accessibilityScheduler = AccessibilityActionScheduler()
    let parser = WhatsAppAppParser()
    let interactor = WhatsAppInteractor()
    let memoryStore = WhatsAppMemoryStore.shared
    lazy var mcpServerCoordinator: MCPServerCoordinator = {
        let coordinator = MCPServerCoordinator(
            dependencies: MCPServerContext(
                runtime: AppModelMCPRuntimeAdapter(appModel: self),
                memoryStore: memoryStore,
                accessibility: accessibility,
                accessibilityScheduler: accessibilityScheduler,
                parser: parser,
                interactor: interactor,
                voiceAssistant: voiceAssistant,
                nicknamesRepository: nicknamesRepository,
                memoriesRepository: memoriesRepository,
                subjectsRepository: subjectsRepository,
                clientVoiceEventsRepository: clientVoiceEventsRepository
            )
        )

        coordinator.setStateHandler { [weak self] state in
            self?.handleMCPStateChange(state)
        }

        coordinator.setCallHandler { [weak self] entry in
            self?.appendServerCall(entry)
        }

        return coordinator
    }()
    let voiceAssistant = VoiceAssistant()
    var pollingTask: Task<Void, Never>?
    var permissionMonitorTask: Task<Void, Never>?
    var listSignaturesById: [String: String] = [:]
    let debugDirectory = URL(fileURLWithPath: "/tmp/AssistantMCPServer", isDirectory: true)
    var cancellables: Set<AnyCancellable> = []
    var liveStatusTask: Task<Void, Never>?
    let serverCallsRepository = ServerCallsRepository.shared
    let nicknamesRepository = NicknamesRepository.shared
    let memoriesRepository = MemoriesRepository.shared
    let subjectsRepository = SubjectsRepository.shared
    let clientVoiceEventsRepository = ClientVoiceEventsRepository.shared
    let chatHistoryRepository = ChatHistoryRepository.shared
    var chatHistoryListenerId: UUID?
    var chatHistoryPersistTask: Task<Void, Never>?

    init(startupMode: StartupMode = .live) {
        let shouldLoadPersistedSettings = startupMode == .live
        voiceSettings = VoiceSettingsModel(loadPersistedValues: shouldLoadPersistedSettings)
        handsFreeClientVoiceSettings = HandsFreeClientVoiceSettingsModel(loadPersistedValues: shouldLoadPersistedSettings)
        inputLockSettings = InputLockSettingsModel(loadPersistedValues: shouldLoadPersistedSettings)
        mcpSendPrefixSettings = MCPSendPrefixSettingsModel(loadPersistedValues: shouldLoadPersistedSettings)

        voiceAssistant.onSpeakingStateChanged = { [weak self] isSpeaking in
            self?.speechSynthesizerSpeaking = isSpeaking
        }

        switch startupMode {
        case .live:
            loadConversationAccessSettings()
            loadAssistantInstructions()
            loadChatListSignatures()
            loadChatHistory()
            bindMemoryStore()
            bindChatHistoryPersistence()
            refreshMicrophoneAuthorization()
            refreshSpeechRecognitionAuthorization()
            bindFeatureSettings()
            Task { [weak self] in
                await self?.markStaleClientVoiceAsLost()
                await self?.refreshPendingClientAskCount()
            }
            Task { [weak self] in
                await self?.loadPersistedServerCalls()
            }
            Task { [weak self] in
                guard let self else { return }
                await self.voiceAssistant.setExperimentalSpeakEnabled(self.voiceSettings.experimentalSpeakApiEnabled)
            }
            refreshStatus()
            startLiveStatusMonitoring()
            Task {
                await startMCPServer()
                startPolling()
            }

        case .preview:
            // Keep previews deterministic and side-effect free.
            assistantInstructions = Self.defaultAssistantInstructions
            runtimeDescription = "Xcode Preview"
            lastRefreshDescription = "Preview"
            microphoneAuthorized = true
            speechRecognitionAuthorized = true
            voiceSettings.experimentalSpeakApiEnabled = true
            handsFreeClientVoiceSettings.isEnabled = false
            handsFreeClientVoiceSettings.debounceSeconds = HandsFreeClientVoiceSettingsModel.defaultDebounceSeconds
        }
    }

    private func bindFeatureSettings() {
        voiceSettings.$experimentalSpeakApiEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                Task {
                    await self.voiceAssistant.setExperimentalSpeakEnabled(enabled)
                }
            }
            .store(in: &cancellables)

        handsFreeClientVoiceSettings.$isEnabled
            .dropFirst()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.maybeShowHandsFreeClientVoiceWindow()
                }
            }
            .store(in: &cancellables)
    }

    func refreshPendingClientAskCount() async {
        let count = await clientVoiceEventsRepository.pendingAskCount()
        pendingClientAskCount = count
        await maybeShowHandsFreeClientVoiceWindow()
    }

    private func markStaleClientVoiceAsLost() async {
        let markedCount = await clientVoiceEventsRepository.markPendingAsLost()
        guard markedCount > 0 else { return }
        appendLog("Marked \(markedCount) stale client voice ask(s) as lost after launch.", level: .warning)
    }

    private func maybeShowHandsFreeClientVoiceWindow() async {
        guard handsFreeClientVoiceSettings.isEnabled else { return }
        let pending = await clientVoiceEventsRepository.list(limit: 50)
            .filter { $0.kind == .ask && $0.askStatus == .pending }
        guard let latest = pending.first else { return }
        let prompt = latest.prompt ?? ""
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ClientVoiceHandsFreeWindowController.shared.show(appModel: self, askId: latest.id, prompt: prompt)
    }

    func refreshMicrophoneAuthorization() {
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func refreshSpeechRecognitionAuthorization() {
        speechRecognitionAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestVoicePermissions() async {
        await requestMicrophonePermission()
        await requestSpeechRecognitionPermission()
    }

    func requestMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneAuthorized = true
        case .notDetermined:
            let granted = await requestMicrophoneAccess()
            microphoneAuthorized = granted
        case .denied, .restricted:
            microphoneAuthorized = false
            openMicrophonePrivacySettings()
        @unknown default:
            microphoneAuthorized = false
        }
        refreshMicrophoneAuthorization()
    }

    func requestSpeechRecognitionPermission() async {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            speechRecognitionAuthorized = true
        case .notDetermined:
            let newStatus = await requestSpeechRecognitionAuthorizationStatus()
            speechRecognitionAuthorized = newStatus == .authorized
        case .denied, .restricted:
            speechRecognitionAuthorized = false
            openSpeechRecognitionPrivacySettings()
        @unknown default:
            speechRecognitionAuthorized = false
        }
        refreshSpeechRecognitionAuthorization()
    }

    private func openMicrophonePrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"
        ]

        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func openSpeechRecognitionPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_SpeechRecognition"
        ]

        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
