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
    @Published private(set) var mcpServerRunning = false
    @Published private(set) var mcpServerStatusDescription = "Stopped"
    @Published private(set) var blockedConversationNames: [String] = []

    private let accessibility = AccessibilityService()
    private let parser = WhatsAppAppParser()
    private let interactor = WhatsAppInteractor()
    private let memoryStore = WhatsAppMemoryStore.shared
    private let mcpConnector: MCPBridgeConnecting = MCPBridgeConnector()
    private var pollingTask: Task<Void, Never>?
    private var permissionMonitorTask: Task<Void, Never>?
    private var listSignaturesById: [String: String] = [:]
    private let debugDirectory = URL(fileURLWithPath: "/tmp/AssistantMCPServer", isDirectory: true)
    private var cancellables: Set<AnyCancellable> = []
    private let blockedConversationDefaultsKey = "blockedConversationNames"

    init() {
        loadBlockedConversationNames()
        bindMemoryStore()
        configureMCPConnector()
        refreshStatus()
        Task {
            await startMCPServer()
        }
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
            let allowedConversations = filteredConversations(screenState.conversations)
            writeDebugArtifacts(snapshot: snapshot, screenState: screenState, prefix: "refresh")
            memoryStore.replaceConversations(allowedConversations)
            lastRefreshDescription = "List refreshed at \(Date().formatted(date: .omitted, time: .standard))"
            appendLog("Parsed \(allowedConversations.count) conversations from WhatsApp.")
            appendLog("Wrote parser debug report to \(debugDirectory.path).")
            await refreshChangedChats(from: allowedConversations)
        } catch {
            appendLog("Failed to refresh conversations: \(error.localizedDescription)", level: .error)
        }
    }

    func openConversation(_ conversation: ConversationSummary) {
        memoryStore.selectConversation(id: conversation.id)
    }

    func isBlocked(_ conversationName: String) -> Bool {
        blockedConversationNames.contains(conversationName)
    }

    func toggleBlockedConversation(_ conversationName: String) {
        if isBlocked(conversationName) {
            unblockConversation(named: conversationName)
        } else {
            blockConversation(named: conversationName)
        }
    }

    func unblockConversation(named conversationName: String) {
        blockedConversationNames.removeAll { $0 == conversationName }
        persistBlockedConversationNames()
        appendLog("Removed \(conversationName) from blacklist.")
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

    func startMCPServer() async {
        mcpConnector.configure(host: mcpServerHost, port: mcpServerPort)

        do {
            try await mcpConnector.start()
            mcpServerRunning = mcpConnector.isRunning
            mcpServerStatusDescription = mcpServerRunning ? "Listening on \(mcpServerAddress)" : "Starting"
            appendLog("MCP HTTP server listening on \(mcpServerAddress).")
        } catch {
            mcpServerRunning = false
            mcpServerStatusDescription = "Failed: \(error.localizedDescription)"
            appendLog("Failed to start MCP server: \(error.localizedDescription)", level: .error)
        }
    }

    func stopMCPServer() async {
        await mcpConnector.stop()
        mcpServerRunning = false
        mcpServerStatusDescription = "Stopped"
        appendLog("Stopped MCP HTTP server.")
    }

    func restartMCPServer() async {
        await stopMCPServer()
        await startMCPServer()
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
            try await sendMessage(trimmedMessage, to: selectedChatState.chat.id)
            messageDraft = ""
        } catch {
            appendLog("Failed to send message: \(error.localizedDescription)", level: .error)
        }
    }

    func sendMessage(_ text: String, to conversationId: String) async throws {
        let trimmedMessage = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw MCPBridgeError.invalidParameter("text")
        }

        guard let conversation = memoryStore.conversation(for: conversationId) else {
            throw MCPBridgeError.invalidParameter("chatId")
        }

        guard !isBlocked(conversation.name) else {
            throw MCPBridgeError.invalidRequest
        }

        guard prepareForWhatsAppInspection() else {
            throw MCPBridgeError.invalidRequest
        }

        try interactor.selectConversation(conversation, using: accessibility)
        try await Task.sleep(for: .milliseconds(650))

        let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
        try interactor.sendMessage(trimmedMessage, in: snapshot, using: accessibility)
        appendLog("Sent message to \(conversation.name).")

        try await Task.sleep(for: .milliseconds(500))

        let refreshedSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
        let refreshedState = parser.parse(snapshot: refreshedSnapshot, messageLimit: 10)
        writeDebugArtifacts(snapshot: refreshedSnapshot, screenState: refreshedState, prefix: "send-\(conversation.id)")
        memoryStore.replaceConversations(refreshedState.conversations)
        updateSelectedChatState(from: refreshedState, preferredConversation: conversation)
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

    private func configureMCPConnector() {
        mcpConnector.setRequestHandler { [weak self] request in
            guard let self else {
                return .failure(MCPBridgeError.invalidRequest)
            }

            return await self.handleMCPRequest(request)
        }
    }

    private func handleMCPRequest(_ request: MCPHTTPRequest) async -> Result<JSONValue, Error> {
        switch request.method {
        case "tools/list":
            return .success(.object(["tools": .array(toolDefinitions.map(\.jsonValue))]))
        case "tools/call":
            guard
                let name = request.params["name"]?.stringValue,
                case .object(let arguments)? = request.params["arguments"]
            else {
                return .failure(MCPBridgeError.invalidRequest)
            }

            return await callTool(MCPToolCall(name: name, arguments: arguments))
        default:
            return .failure(MCPBridgeError.unsupportedMethod(request.method))
        }
    }

    private var toolDefinitions: [MCPToolDefinition] {
        [
            MCPToolDefinition(
                name: "list_chats",
                description: "Lists the chats currently mapped in memory from WhatsApp.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([:])
                ]
            ),
            MCPToolDefinition(
                name: "get_recent_messages",
                description: "Returns recent messages for a mapped chat.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "chatId": .object(["type": .string("string")]),
                        "limit": .object(["type": .string("number")])
                    ]),
                    "required": .array([.string("chatId")])
                ]
            ),
            MCPToolDefinition(
                name: "send_message",
                description: "Sends a message to a mapped chat through Accessibility.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "chatId": .object(["type": .string("string")]),
                        "text": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("chatId"), .string("text")])
                ]
            ),
            MCPToolDefinition(
                name: "wait_for_message",
                description: "Waits until a new message appears in memory and returns it.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "chatId": .object(["type": .string("string")]),
                        "afterMessageId": .object(["type": .string("string")]),
                        "timeoutSeconds": .object(["type": .string("number")])
                    ])
                ]
            )
        ]
    }

    private func callTool(_ call: MCPToolCall) async -> Result<JSONValue, Error> {
        switch call.name {
        case "list_chats":
            let chats = memoryStore.conversations.map(conversationJSONValue)
            return .success(.object(["chats": .array(chats)]))
        case "get_recent_messages":
            guard let chatId = call.arguments["chatId"]?.stringValue else {
                return .failure(MCPBridgeError.missingParameter("chatId"))
            }

            let limit = max(1, call.arguments["limit"]?.intValue ?? 10)
            guard let chatState = memoryStore.chatState(for: chatId) else {
                return .success(.object(["chat": .null, "messages": .array([])]))
            }

            let messages = chatState.messages.suffix(limit).map(messageJSONValue)
            return .success(.object([
                "chat": conversationJSONValue(chatState.chat),
                "messages": .array(messages)
            ]))
        case "send_message":
            guard let chatId = call.arguments["chatId"]?.stringValue else {
                return .failure(MCPBridgeError.missingParameter("chatId"))
            }

            guard let text = call.arguments["text"]?.stringValue else {
                return .failure(MCPBridgeError.missingParameter("text"))
            }

            do {
                try await sendMessage(text, to: chatId)
                return .success(.object([
                    "ok": .bool(true),
                    "chatId": .string(chatId)
                ]))
            } catch {
                return .failure(error)
            }
        case "wait_for_message":
            let timeoutSeconds = max(1, call.arguments["timeoutSeconds"]?.intValue ?? 60)
            let result = await memoryStore.waitForNextMessage(
                chatId: call.arguments["chatId"]?.stringValue,
                afterMessageId: call.arguments["afterMessageId"]?.stringValue,
                timeoutSeconds: timeoutSeconds
            )

            if let result {
                return .success(.object([
                    "timedOut": .bool(false),
                    "chat": conversationJSONValue(result.chat),
                    "message": messageJSONValue(result.message)
                ]))
            }

            return .success(.object(["timedOut": .bool(true)]))
        default:
            return .failure(MCPBridgeError.invalidParameter("name"))
        }
    }

    private func conversationJSONValue(_ conversation: ConversationSummary) -> JSONValue {
        .object([
            "id": .string(conversation.id),
            "name": .string(conversation.name),
            "unreadCount": .number(Double(conversation.unreadCount)),
            "isPinned": .bool(conversation.isPinned),
            "isSelected": .bool(conversation.isSelected),
            "lastMessagePreview": conversation.lastMessagePreview.map(JSONValue.string) ?? .null,
            "lastMessageAtText": conversation.lastMessageAtText.map(JSONValue.string) ?? .null,
            "lastMessageDirection": .string(conversation.lastMessageDirection.rawValue),
            "lastMessageStatus": .string(conversation.lastMessageStatus.rawValue),
            "isTyping": .bool(conversation.isTyping)
        ])
    }

    private func messageJSONValue(_ message: Message) -> JSONValue {
        .object([
            "id": .string(message.id),
            "chatId": .string(message.chatId),
            "direction": .string(message.direction.rawValue),
            "kind": .string(message.kind.rawValue),
            "text": message.text.map(JSONValue.string) ?? .null,
            "durationSeconds": message.durationSeconds.map(JSONValue.number) ?? .null,
            "timestamp": .from(date: message.timestamp),
            "status": .string(message.status.rawValue),
            "rawAccessibilityText": .string(message.rawAccessibilityText)
        ])
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

    private func filteredConversations(_ conversations: [ConversationSummary]) -> [ConversationSummary] {
        conversations.filter { !isBlocked($0.name) }
    }

    private func blockConversation(named conversationName: String) {
        guard !isBlocked(conversationName) else {
            return
        }

        blockedConversationNames.append(conversationName)
        blockedConversationNames.sort()
        persistBlockedConversationNames()

        let blockedIDs = conversations
            .filter { $0.name == conversationName }
            .map(\.id)

        for blockedID in blockedIDs {
            listSignaturesById.removeValue(forKey: blockedID)
            memoryStore.removeConversation(id: blockedID)
        }

        appendLog("Added \(conversationName) to blacklist.")
    }

    private func loadBlockedConversationNames() {
        blockedConversationNames = UserDefaults.standard.stringArray(forKey: blockedConversationDefaultsKey) ?? []
        blockedConversationNames.sort()
    }

    private func persistBlockedConversationNames() {
        UserDefaults.standard.set(blockedConversationNames, forKey: blockedConversationDefaultsKey)
    }
}
