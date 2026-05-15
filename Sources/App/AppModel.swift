import AVFoundation
import AppKit
import Combine
import Foundation
import MCP

@MainActor
final class AppModel: ObservableObject {
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
    @Published var speechVoiceIdentifier: String?
    @Published var speechLanguage = "pt-BR"
    @Published var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var recognitionLocaleIdentifier = "pt-BR"
    @Published var experimentalInputLockEnabled = false
    @Published var mcpSendMessagePrefix = ""
    @Published var pendingClientAskCount = 0
    @Published var microphoneAuthorized = true

    let accessibility = AccessibilityService()
    let accessibilityScheduler = AccessibilityActionScheduler()
    let parser = WhatsAppAppParser()
    let interactor = WhatsAppInteractor()
    let memoryStore = WhatsAppMemoryStore.shared
    let mcpConnector = MCPHTTPServer()
    let voiceAssistant = VoiceAssistant()
    var mcpServer: Server?
    var mcpTransport: StatelessHTTPServerTransport?
    var pollingTask: Task<Void, Never>?
    var permissionMonitorTask: Task<Void, Never>?
    var listSignaturesById: [String: String] = [:]
    let debugDirectory = URL(fileURLWithPath: "/tmp/AssistantMCPServer", isDirectory: true)
    var cancellables: Set<AnyCancellable> = []
    var mcpRestartTask: Task<Void, Never>?
    var liveStatusTask: Task<Void, Never>?
    let serverCallsRepository = ServerCallsRepository.shared
    let nicknamesRepository = NicknamesRepository.shared
    let memoriesRepository = MemoriesRepository.shared
    let subjectsRepository = SubjectsRepository.shared
    let clientVoiceEventsRepository = ClientVoiceEventsRepository.shared

    init() {
        loadConversationAccessSettings()
        loadAssistantInstructions()
        loadVoiceSettings()
        loadExperimentalInputLockSetting()
        loadMCPSendMessagePrefixSetting()
        loadChatListSignatures()
        bindMemoryStore()
        configureMCPConnector()
        refreshMicrophoneAuthorization()
        Task { [weak self] in
            await self?.refreshPendingClientAskCount()
        }
        Task { [weak self] in
            await self?.loadPersistedServerCalls()
        }
        refreshStatus()
        startLiveStatusMonitoring()
        Task {
            await startMCPServer()
            startPolling()
        }
    }

    func refreshPendingClientAskCount() async {
        let count = await clientVoiceEventsRepository.pendingAskCount()
        pendingClientAskCount = count
    }

    func refreshMicrophoneAuthorization() {
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneAuthorized = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneAuthorized = granted
        case .denied, .restricted:
            microphoneAuthorized = false
        @unknown default:
            microphoneAuthorized = false
        }
    }
}
