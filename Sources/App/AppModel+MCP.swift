import Foundation

extension AppModel {
    var mcpServerAddress: String {
        "\(mcpServerHost):\(mcpServerPort)"
    }

    var mcpConfigurationSnippet: String {
        """
        [mcp_servers.assistant_whatsapp]
        enabled = true
        url = "http://localhost:\(mcpServerPort)/mcp"
        """
    }

    func updateMCPServerPortText(_ value: String) {
        let digitsOnly = String(value.filter(\.isNumber))
        let trimmedDigits = String(digitsOnly.prefix(5))
        mcpServerPortText = trimmedDigits

        guard let port = Int(trimmedDigits), (1024...65535).contains(port) else {
            return
        }

        mcpServerPort = port
    }

    func startMCPServer() async {
        mcpConnector.configure(host: mcpServerHost, port: mcpServerPort)

        do {
            try await mcpConnector.start()
        } catch {
            mcpServerRunning = false
            mcpServerStatusDescription = "Failed: \(error.localizedDescription)"
            appendLog("Failed to start MCP server: \(error.localizedDescription)", level: .error)
            scheduleMCPRestart()
        }
    }

    func stopMCPServer() async {
        mcpRestartTask?.cancel()
        mcpRestartTask = nil
        await mcpConnector.stop()
        mcpServerRunning = false
        mcpServerStatusDescription = "Stopped"
    }

    func restartMCPServer() async {
        await stopMCPServer()
        await startMCPServer()
    }

    func configureMCPConnector() {
        mcpConnector.setRequestHandler { [weak self] request in
            guard let self else {
                return .failure(MCPServerError.invalidRequest)
            }

            return await self.handleMCPRequest(request)
        }

        mcpConnector.setStateHandler { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleMCPStateChange(state)
            }
        }
    }

    private func handleMCPStateChange(_ state: MCPServerState) {
        switch state {
        case .starting(let port):
            mcpServerRunning = false
            mcpServerStatusDescription = "Starting on localhost:\(port)"
            appendLog("Starting MCP HTTP server on localhost:\(port).")
        case .ready(let port):
            mcpRestartTask?.cancel()
            mcpRestartTask = nil
            mcpServerRunning = true
            mcpServerStatusDescription = "Listening on localhost:\(port)"
            appendLog("MCP HTTP server listening on localhost:\(port).")
        case .failed(let message):
            mcpServerRunning = false
            mcpServerStatusDescription = "Failed: \(message)"
            appendLog("MCP HTTP server failed: \(message)", level: .error)
            scheduleMCPRestart()
        case .stopped:
            mcpServerRunning = false
            mcpServerStatusDescription = "Stopped"
            appendLog("MCP HTTP server stopped.", level: .warning)
        }
    }

    private func scheduleMCPRestart() {
        guard mcpRestartTask == nil else {
            return
        }

        mcpRestartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.appendLog("Retrying MCP HTTP server startup.", level: .warning)
            }
            await self?.startMCPServer()
            await MainActor.run {
                self?.mcpRestartTask = nil
            }
        }
    }

    private func handleMCPRequest(_ request: MCPHTTPRequest) async -> Result<JSONValue, Error> {
        switch request.method {
        case "initialize":
            return .success(.object([
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .object([
                    "tools": .object([:])
                ]),
                "serverInfo": .object([
                    "name": .string("assistant-whatsapp"),
                    "version": .string("0.1.0")
                ])
            ]))
        case "ping", "notifications/initialized":
            return .success(.object([:]))
        case "tools/list":
            return .success(.object(["tools": .array(toolDefinitions.map(\.jsonValue))]))
        case "tools/call":
            guard
                let name = request.params["name"]?.stringValue,
                case .object(let arguments)? = request.params["arguments"]
            else {
                return .failure(MCPServerError.invalidRequest)
            }

            return await callTool(MCPToolCall(name: name, arguments: arguments))
        default:
            return .failure(MCPServerError.unsupportedMethod(request.method))
        }
    }

    private var toolDefinitions: [MCPToolDefinition] {
        [
            MCPToolDefinition(
                name: "list_chats",
                description: "Lists relevant chats from WhatsApp.",
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
                return .failure(MCPServerError.missingParameter("chatId"))
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
                return .failure(MCPServerError.missingParameter("chatId"))
            }

            guard let text = call.arguments["text"]?.stringValue else {
                return .failure(MCPServerError.missingParameter("text"))
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
//            let timeoutSeconds = max(1, call.arguments["timeoutSeconds"]?.intValue ?? 60)
            let result = await memoryStore.waitForNextMessage(
                chatId: call.arguments["chatId"]?.stringValue,
                afterMessageId: call.arguments["afterMessageId"]?.stringValue,
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
            return .failure(MCPServerError.invalidParameter("name"))
        }
    }

    private func conversationJSONValue(_ conversation: ConversationSummary) -> JSONValue {
        .object([
            "id": .string(conversation.id),
            "name": .string(conversation.name),
            "unreadCount": .number(Double(conversation.unreadCount)),
//            "isPinned": .bool(conversation.isPinned),
//            "isSelected": .bool(conversation.isSelected),
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
}
