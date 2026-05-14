import AVFoundation
import AppKit
import Combine
import Foundation
import MCP

@MainActor
final class AppModel: ObservableObject {
    @Published var logs: [LogEntry] = []
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
    @Published var blockedConversationNames: [String] = []
    @Published var debugSnapshot: WhatsAppSnapshot?
    @Published var debugNodePath: [Int] = []
    @Published var assistantInstructions = ""
    @Published var speechVoiceIdentifier: String?
    @Published var speechLanguage = "pt-BR"
    @Published var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var recognitionLocaleIdentifier = "pt-BR"

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
    let blockedConversationDefaultsKey = "blockedConversationNames"
    let assistantInstructionsDefaultsKey = "assistantInstructions"
    let speechVoiceIdentifierDefaultsKey = "speechVoiceIdentifier"
    let speechLanguageDefaultsKey = "speechLanguage"
    let speechRateDefaultsKey = "speechRate"
    let recognitionLocaleIdentifierDefaultsKey = "recognitionLocaleIdentifier"
    let chatListSignaturesDefaultsKey = "chatListSignatures.v1"
    var mcpRestartTask: Task<Void, Never>?
    var liveStatusTask: Task<Void, Never>?

    init() {
        loadBlockedConversationNames()
        loadAssistantInstructions()
        loadVoiceSettings()
        loadChatListSignatures()
        bindMemoryStore()
        configureMCPConnector()
        refreshStatus()
        startLiveStatusMonitoring()
        Task {
            await startMCPServer()
            startPolling()
        }
    }
}
