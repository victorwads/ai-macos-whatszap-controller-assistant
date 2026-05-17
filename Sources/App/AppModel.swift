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
    @Published var pollingIntervalSeconds = 5
    @Published var mcpServerHost = "localhost"
    @Published var mcpServerPort = 8080
    @Published var mcpServerPortText = "8080"
    @Published var mcpServerRunning = false
    @Published var mcpServerStatusDescription = "Stopped"
    @Published var conversationAccessMode: ConversationAccessMode = .allowAllExceptDeny
    @Published var denyConversationNames: [String] = []
    @Published var allowConversationNames: [String] = []
    @Published var pendingClientAskCount = 0
    @Published var pendingClientPromptWaitCount = 0
    @Published var microphoneAuthorized = true
    @Published var speechRecognitionAuthorized = true
    @Published var speechSynthesizerSpeaking = false
    @Published var whatsAppWebAccounts: [WhatsAppWebAccount] = []
    @Published var selectedWhatsAppWebAccountId: UUID?
    @Published var whatsAppWebPageSnapshotsByAccountId: [UUID: WhatsAppWebPageSnapshot] = [:]

    let voiceSettings: VoiceSettingsModel
    let handsFreeClientVoiceSettings: HandsFreeClientVoiceSettingsModel
    let inputLockSettings: InputLockSettingsModel
    let mcpSendPrefixSettings: MCPSendPrefixSettingsModel
    let whatsAppWebSettings: WhatsAppWebSettingsModel

    let accessibility = AccessibilityService()
    let accessibilityScheduler = AccessibilityActionScheduler()
    let parser = WhatsAppAppParser()
    let whatsAppWebSessionStore = WhatsAppWebSessionStore()
    let whatsAppWebBridge = WhatsAppWebBridge()
    lazy var whatsAppWebDebugCaptureService = WhatsAppWebDebugCaptureService(
        log: { [weak self] message, level in
            self?.appendLog(message, level: level)
        }
    )
    let clientPromptWaitRepository = ClientPromptWaitRepository.shared
    lazy var whatsappMessageSendCoordinator = WhatsAppMessageSendCoordinator(
        accessibility: accessibility,
        accessibilityScheduler: accessibilityScheduler,
        parser: parser,
        interactor: interactor,
        inputLockSettings: inputLockSettings,
        isPolling: { [weak self] in
            self?.isPolling ?? false
        },
        stopPolling: { [weak self] in
            self?.stopPolling()
        },
        startPolling: { [weak self] in
            self?.startPolling()
        },
        resolveConversation: { [weak self] conversationId in
            self?.memoryStore.conversation(for: conversationId)
        },
        isBlocked: { [weak self] conversationName in
            self?.isBlocked(conversationName) ?? false
        },
        openConversationAndCapture: { [weak self] conversation in
            guard let self else {
                throw CancellationError()
            }
            return try await self.openConversationAndCapture(conversation)
        },
        updateSelectedChatState: { [weak self] screenState, preferredConversation in
            self?.updateSelectedChatState(from: screenState, preferredConversation: preferredConversation)
        },
        appendLog: { [weak self] message, level in
            self?.appendLog(message, level: level)
        }
    )
    lazy var whatsAppDebugService = WhatsAppDebugCaptureService(
        accessibility: accessibility,
        parser: parser,
        log: { [weak self] message, level in
            self?.appendLog(message, level: level)
        }
    )
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
                sensitiveDataRepository: sensitiveDataRepository,
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
    var whatsAppWebBridgePollingTask: Task<Void, Never>?
    var permissionMonitorTask: Task<Void, Never>?
    var listSignaturesById: [String: String] = [:]
    var cancellables: Set<AnyCancellable> = []
    var liveStatusTask: Task<Void, Never>?
    let serverCallsRepository = ServerCallsRepository.shared
    let nicknamesRepository = NicknamesRepository.shared
    let memoriesRepository = MemoriesRepository.shared
    let sensitiveDataRepository = SensitiveDataRepository.shared
    let subjectsRepository = SubjectsRepository.shared
    let whatsAppWebAccountsRepository = WhatsAppWebAccountsRepository.shared
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
        whatsAppWebSettings = WhatsAppWebSettingsModel(loadPersistedValues: shouldLoadPersistedSettings)
        whatsAppWebSessionStore.setCustomUserAgent(whatsAppWebSettings.effectiveCustomUserAgent)
        whatsAppWebSessionStore.setInspectable(whatsAppWebSettings.isInspectable)
        whatsAppWebSessionStore.setPageZoom(whatsAppWebSettings.pageZoom)

        voiceAssistant.onSpeakingStateChanged = { [weak self] isSpeaking in
            self?.speechSynthesizerSpeaking = isSpeaking
        }

        switch startupMode {
        case .live:
            loadConversationAccessSettings()
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
            await self?.refreshPendingClientPromptWaitCount()
            await self?.loadWhatsAppWebAccounts()
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
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.voiceAssistant.setExperimentalSpeakEnabled(enabled)
                }
            }
            .store(in: &cancellables)

        handsFreeClientVoiceSettings.$isEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.maybeShowHandsFreeClientVoiceWindow()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .clientVoiceEventsRepositoryDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshPendingClientAskCount()
                }
            }
            .store(in: &cancellables)

        whatsAppWebSettings.$customUserAgent
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.whatsAppWebSessionStore.setCustomUserAgent(value)
            }
            .store(in: &cancellables)

        whatsAppWebSettings.$isInspectable
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.whatsAppWebSessionStore.setInspectable(value)
            }
            .store(in: &cancellables)

        whatsAppWebSettings.$bridgePollingEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.restartWhatsAppWebBridgePolling()
            }
            .store(in: &cancellables)

        whatsAppWebSettings.$bridgePollingIntervalSeconds
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.restartWhatsAppWebBridgePolling()
            }
            .store(in: &cancellables)

        whatsAppWebSettings.$pageZoom
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.whatsAppWebSessionStore.setPageZoom(value)
            }
            .store(in: &cancellables)
    }

    func refreshPendingClientAskCount() async {
        let count = await clientVoiceEventsRepository.pendingAskCount()
        pendingClientAskCount = count
        await maybeShowHandsFreeClientVoiceWindow()
    }

    func refreshPendingClientPromptWaitCount() async {
        pendingClientPromptWaitCount = await clientPromptWaitRepository.pendingWaitCount()
    }

    func beginClientPromptWait() async -> UUID {
        let id = await clientPromptWaitRepository.beginWait()
        await refreshPendingClientPromptWaitCount()
        return id
    }

    func endClientPromptWait(id: UUID) async {
        await clientPromptWaitRepository.endWait(id: id)
        await refreshPendingClientPromptWaitCount()
    }

    func submitClientPrompt(_ text: String) async {
        await clientPromptWaitRepository.submitPrompt(text)
    }

    func consumeClientPrompt() async -> String? {
        await clientPromptWaitRepository.consumePrompt()
    }

    private func markStaleClientVoiceAsLost() async {
        let markedCount = await clientVoiceEventsRepository.markPendingAsLost()
        guard markedCount > 0 else { return }
        appendLog("Marked \(markedCount) stale client voice ask(s) as lost after launch.", level: .warning)
    }

    private func maybeShowHandsFreeClientVoiceWindow() async {
        guard handsFreeClientVoiceSettings.isEnabled else { return }
        await showLatestPendingClientAskWindow(force: false)
    }

    func openPendingClientAskWindow() async {
        await showLatestPendingClientAskWindow(force: true)
    }

    func openPendingClientPromptWindow() {
        ClientVoicePromptWindowController.shared.show(appModel: self)
    }

    private func showLatestPendingClientAskWindow(force: Bool) async {
        let pending = await clientVoiceEventsRepository.list(limit: 50)
            .filter { $0.kind == .ask && $0.askStatus == .pending }
        guard let latest = pending.first else { return }
        let prompt = latest.prompt ?? ""
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if force || handsFreeClientVoiceSettings.isEnabled {
            ClientVoiceHandsFreeWindowController.shared.show(appModel: self, askId: latest.id, prompt: prompt)
        }
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
