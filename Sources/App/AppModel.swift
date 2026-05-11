import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var whatsappRunning = false
    @Published private(set) var runtimeDescription = ""
    @Published private(set) var conversations: [ConversationSummary] = []
    @Published private(set) var selectedConversationId: String?
    @Published private(set) var selectedChatState: ChatState?
    @Published private(set) var isPolling = false
    @Published private(set) var lastRefreshDescription = "Never refreshed"
    @Published private(set) var waitingForAccessibilityRelaunch = false
    @Published var messageDraft = ""
    @Published private(set) var isSendingMessage = false
    @Published var pollingIntervalSeconds = 3
    @Published var mcpServerHost = "localhost"
    @Published var mcpServerPort = 8080

    private let accessibility = AccessibilityService()
    private let parser = WhatsAppAppParser()
    private let interactor = WhatsAppInteractor()
    private let memoryStore = WhatsAppMemoryStore.shared
    private var pollingTask: Task<Void, Never>?
    private var permissionMonitorTask: Task<Void, Never>?
    private var listSignaturesById: [String: String] = [:]
    private let debugDirectory = URL(fileURLWithPath: "/tmp/AssistantMCPServer", isDirectory: true)
    private var cancellables: Set<AnyCancellable> = []

    init() {
        bindMemoryStore()
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
        if accessibility.isTrusted(prompt: false) {
            accessibilityTrusted = true
            appendLog("Accessibility is already trusted for this app identity.")
            return
        }

        _ = accessibility.isTrusted(prompt: true)
        appendLog("Requested Accessibility permission from macOS.")
        appendLog("After enabling the app in System Settings, this app will relaunch itself.")
        appendLog("If permission resets after every build, configure a stable Apple Development signing identity for Debug.", level: .warning)
        refreshStatus()
        startPermissionMonitor()
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
            let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            writeDebugArtifacts(snapshot: snapshot, screenState: parser.parse(snapshot: snapshot, messageLimit: 10), prefix: "manual-dump")
            appendLog("Captured WhatsApp Accessibility snapshot.")
            appendLog("Wrote debug files to \(debugDirectory.path).")
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
            let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let screenState = parser.parse(snapshot: snapshot, messageLimit: 10)
            writeDebugArtifacts(snapshot: snapshot, screenState: screenState, prefix: "refresh")
            memoryStore.replaceConversations(screenState.conversations)
            lastRefreshDescription = "List refreshed at \(Date().formatted(date: .omitted, time: .standard))"
            appendLog("Parsed \(screenState.conversations.count) conversations from WhatsApp.")
            appendLog("Wrote parser debug report to \(debugDirectory.path).")
            await refreshChangedChats(from: screenState.conversations)
        } catch {
            appendLog("Failed to refresh conversations: \(error.localizedDescription)", level: .error)
        }
    }

    func openConversation(_ conversation: ConversationSummary) {
        memoryStore.selectConversation(id: conversation.id)
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
                try? await Task.sleep(for: .seconds(self.pollingIntervalSeconds))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
        appendLog("Stopped WhatsApp polling.")
    }

    var mcpServerAddress: String {
        "\(mcpServerHost):\(mcpServerPort)"
    }

    var mcpConfigurationSnippet: String {
        """
        {
          "mcpServers": {
            "assistant-whatsapp": {
              "transport": {
                "type": "http",
                "url": "http://\(mcpServerAddress)/mcp"
              }
            }
          }
        }
        """
    }

    func sendMessageToSelectedChat() async {
        let trimmedMessage = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            appendLog("Cannot send an empty message.", level: .warning)
            return
        }

        guard let selectedChatState else {
            appendLog("No selected conversation available to send a message.", level: .warning)
            return
        }

        guard prepareForWhatsAppInspection() else {
            return
        }

        isSendingMessage = true
        defer { isSendingMessage = false }

        do {
            try interactor.selectConversation(selectedChatState.chat, using: accessibility)
            try await Task.sleep(for: .milliseconds(650))

            let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            try interactor.sendMessage(trimmedMessage, in: snapshot, using: accessibility)
            messageDraft = ""
            appendLog("Sent message to \(selectedChatState.chat.name).")

            try await Task.sleep(for: .milliseconds(500))

            let refreshedSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let refreshedState = parser.parse(snapshot: refreshedSnapshot, messageLimit: 10)
            writeDebugArtifacts(snapshot: refreshedSnapshot, screenState: refreshedState, prefix: "send-\(selectedChatState.chat.id)")
            memoryStore.replaceConversations(refreshedState.conversations)
            updateSelectedChatState(from: refreshedState, preferredConversation: selectedChatState.chat)
        } catch {
            appendLog("Failed to send message: \(error.localizedDescription)", level: .error)
        }
    }

    private func startPermissionMonitor() {
        permissionMonitorTask?.cancel()
        waitingForAccessibilityRelaunch = true

        permissionMonitorTask = Task { [weak self] in
            guard let self else { return }

            for _ in 0..<120 {
                guard !Task.isCancelled else { return }

                if self.accessibility.isTrusted(prompt: false) {
                    self.accessibilityTrusted = true
                    self.waitingForAccessibilityRelaunch = false
                    self.appendLog("Accessibility permission is now trusted. Relaunching app.")
                    self.relaunchCurrentApp()
                    return
                }

                try? await Task.sleep(for: .seconds(1))
            }

            self.waitingForAccessibilityRelaunch = false
            self.appendLog("Timed out waiting for Accessibility permission. Press Permission again after changing System Settings.", level: .warning)
        }
    }

    private func relaunchCurrentApp() {
        let bundleURL = Bundle.main.bundleURL

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", bundleURL.path]
            try process.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        } catch {
            appendLog("Failed to relaunch app automatically: \(error.localizedDescription)", level: .error)
        }
    }

    private func refreshChangedChats(from conversations: [ConversationSummary]) async {
        for conversation in conversations {
            let previousSignature = listSignaturesById[conversation.id]
            let needsMessages = memoryStore.chatState(for: conversation.id) == nil || previousSignature != conversation.listSignature
            listSignaturesById[conversation.id] = conversation.listSignature

            guard needsMessages else {
                continue
            }

            await loadMessages(
                for: conversation,
                reason: previousSignature == nil ? "first mapping" : "list changed",
                updateSelectedChat: selectedChatState?.chat.id == conversation.id
            )
        }
    }

    private func loadMessages(for conversation: ConversationSummary, reason: String, updateSelectedChat: Bool) async {
        do {
            try interactor.selectConversation(conversation, using: accessibility)
            try await Task.sleep(for: .milliseconds(650))

            let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let screenState = parser.parse(snapshot: snapshot, messageLimit: 10)
            writeDebugArtifacts(snapshot: snapshot, screenState: screenState, prefix: "chat-\(conversation.id)")
            let chatState = makeChatState(from: screenState, preferredConversation: conversation)
            memoryStore.upsertChatState(chatState)
            appendLog("Loaded \(screenState.messages.count) messages for \(conversation.name) (\(reason)).")
        } catch {
            appendLog("Failed to load messages for \(conversation.name): \(error.localizedDescription)", level: .error)
        }
    }

    private func updateSelectedChatState(from screenState: WhatsAppScreenState, preferredConversation: ConversationSummary) {
        let chatState = makeChatState(from: screenState, preferredConversation: preferredConversation)
        memoryStore.upsertChatState(chatState)
    }

    private func makeChatState(from screenState: WhatsAppScreenState, preferredConversation: ConversationSummary) -> ChatState {
        let latestConversation = screenState.conversations.first { $0.id == preferredConversation.id } ?? preferredConversation

        return ChatState(
            chat: latestConversation,
            messages: screenState.messages,
            composeFocused: screenState.composeFocused,
            canSendText: screenState.canSendText
        )
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

    private func bindMemoryStore() {
        memoryStore.$conversations
            .sink { [weak self] in
                self?.conversations = $0
            }
            .store(in: &cancellables)

        memoryStore.$selectedChatState
            .sink { [weak self] in
                self?.selectedChatState = $0
            }
            .store(in: &cancellables)

        memoryStore.$selectedConversationId
            .sink { [weak self] in
                self?.selectedConversationId = $0
            }
            .store(in: &cancellables)
    }

    private func writeDebugArtifacts(snapshot: WhatsAppSnapshot, screenState: WhatsAppScreenState, prefix: String) {
        do {
            try FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
            try snapshot.prettyDescription.write(to: debugDirectory.appendingPathComponent("latest-snapshot.txt"), atomically: true, encoding: .utf8)
            try parser.debugReport(snapshot: snapshot).write(to: debugDirectory.appendingPathComponent("latest-parser-report.txt"), atomically: true, encoding: .utf8)
            try conversationReport(screenState).write(to: debugDirectory.appendingPathComponent("latest-state.txt"), atomically: true, encoding: .utf8)

            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try parser.debugReport(snapshot: snapshot).write(to: debugDirectory.appendingPathComponent("\(timestamp)-\(prefix)-parser-report.txt"), atomically: true, encoding: .utf8)
        } catch {
            appendLog("Failed to write parser debug artifacts: \(error.localizedDescription)", level: .warning)
        }
    }

    private func conversationReport(_ screenState: WhatsAppScreenState) -> String {
        let conversations = screenState.conversations.map { conversation in
            "- \(conversation.name) | unread=\(conversation.unreadCount) | date=\(conversation.lastMessageAtText ?? "nil") | preview=\(conversation.lastMessagePreview ?? "nil")"
        }.joined(separator: "\n")

        let messages = screenState.messages.map { message in
            "- \(message.direction.rawValue) \(message.status.rawValue): \(message.text ?? message.rawAccessibilityText)"
        }.joined(separator: "\n")

        return """
        Conversations:
        \(conversations.isEmpty ? "- none" : conversations)

        Messages:
        \(messages.isEmpty ? "- none" : messages)
        """
    }
}
