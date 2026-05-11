import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var whatsappRunning = false
    @Published private(set) var runtimeDescription = ""
    @Published private(set) var conversations: [ConversationSummary] = []
    @Published private(set) var selectedChatState: ChatState?
    @Published private(set) var isPolling = false
    @Published private(set) var lastRefreshDescription = "Never refreshed"

    private let accessibility = AccessibilityService()
    private let parser = WhatsAppScreenParser()
    private var pollingTask: Task<Void, Never>?
    private var chatStatesById: [String: ChatState] = [:]
    private var listSignaturesById: [String: String] = [:]

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        accessibilityTrusted = accessibility.isTrusted(prompt: false)
        whatsappRunning = accessibility.findWhatsAppApplication() != nil
        runtimeDescription = accessibility.currentAppIdentityDescription()

        appendLog("Accessibility trusted: \(accessibilityTrusted ? "yes" : "no")")
        appendLog("WhatsApp running: \(whatsappRunning ? "yes" : "no")")
        appendLog(runtimeDescription)
    }

    func requestAccessibilityPermission() {
        _ = accessibility.isTrusted(prompt: true)
        appendLog("Requested Accessibility permission from macOS.")
        appendLog("If permission was just enabled, relaunch this app from Xcode and press Refresh.")
        refreshStatus()
    }

    func dumpWhatsAppSnapshot() {
        // TCC can change while the app is open, so never trust only the cached UI state here.
        let trustedNow = accessibility.isTrusted(prompt: false)
        accessibilityTrusted = trustedNow

        guard trustedNow else {
            appendLog("Cannot inspect WhatsApp before Accessibility permission is granted to this exact app binary.", level: .warning)
            appendLog(accessibility.currentAppIdentityDescription(), level: .warning)
            appendLog("When running from Xcode, macOS may require granting permission to the built app in DerivedData and then relaunching it.", level: .warning)
            return
        }

        do {
            let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 5)
            appendLog("Captured WhatsApp Accessibility snapshot.")
            appendLog(snapshot.prettyDescription)
        } catch {
            appendLog("Failed to capture WhatsApp snapshot: \(error.localizedDescription)", level: .error)
        }
    }

    func refreshConversations() async {
        guard prepareForWhatsAppInspection() else {
            return
        }

        do {
            let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 8)
            let screenState = parser.parse(snapshot: snapshot, messageLimit: 10)
            conversations = screenState.conversations
            lastRefreshDescription = "List refreshed at \(Date().formatted(date: .omitted, time: .standard))"
            appendLog("Parsed \(screenState.conversations.count) conversations from WhatsApp.")
            await refreshChangedChats(from: screenState.conversations)
        } catch {
            appendLog("Failed to refresh conversations: \(error.localizedDescription)", level: .error)
        }
    }

    func openConversation(_ conversation: ConversationSummary) async {
        guard prepareForWhatsAppInspection() else {
            return
        }

        await loadMessages(for: conversation, reason: "manual selection")
    }

    func startPolling() {
        guard pollingTask == nil else {
            return
        }

        isPolling = true
        appendLog("Started WhatsApp polling.")

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshConversations()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
        appendLog("Stopped WhatsApp polling.")
    }

    private func refreshChangedChats(from conversations: [ConversationSummary]) async {
        for conversation in conversations {
            let previousSignature = listSignaturesById[conversation.id]
            let needsMessages = chatStatesById[conversation.id] == nil || previousSignature != conversation.listSignature
            listSignaturesById[conversation.id] = conversation.listSignature

            guard needsMessages else {
                continue
            }

            await loadMessages(for: conversation, reason: previousSignature == nil ? "first mapping" : "list changed")
        }
    }

    private func loadMessages(for conversation: ConversationSummary, reason: String) async {
        do {
            try accessibility.pressNode(at: conversation.accessibilityPath)
            try await Task.sleep(for: .milliseconds(650))

            let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 9)
            let screenState = parser.parse(snapshot: snapshot, messageLimit: 10)
            let latestConversation = screenState.conversations.first { $0.id == conversation.id } ?? conversation

            let chatState = ChatState(
                chat: latestConversation,
                messages: screenState.messages,
                composeFocused: screenState.composeFocused,
                canSendText: screenState.canSendText
            )

            chatStatesById[conversation.id] = chatState
            selectedChatState = chatState
            appendLog("Loaded \(screenState.messages.count) messages for \(conversation.name) (\(reason)).")
        } catch {
            appendLog("Failed to load messages for \(conversation.name): \(error.localizedDescription)", level: .error)
        }
    }

    private func prepareForWhatsAppInspection() -> Bool {
        let trustedNow = accessibility.isTrusted(prompt: false)
        accessibilityTrusted = trustedNow
        whatsappRunning = accessibility.findWhatsAppApplication() != nil

        guard trustedNow else {
            appendLog("Cannot inspect WhatsApp before Accessibility permission is granted.", level: .warning)
            return false
        }

        guard whatsappRunning else {
            appendLog("Cannot inspect WhatsApp because it is not running.", level: .warning)
            return false
        }

        return true
    }

    private func appendLog(_ message: String, level: LogLevel = .info) {
        logs.append(LogEntry(level: level, message: message))
    }
}
