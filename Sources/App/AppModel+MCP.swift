import AVFoundation
import Foundation
import MCP

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

        let server = Server(
            name: "assistant-whatsapp",
            version: "0.1.0",
            capabilities: .init(
                tools: .init(listChanged: true)
            )
        )

        let transport = StatelessHTTPServerTransport()

        await configureMCPHandlers(server)

        do {
            try await server.start(transport: transport)
            mcpServer = server
            mcpTransport = transport
            mcpConnector.setTransport(transport)
            try await mcpConnector.start()
        } catch {
            await server.stop()
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
        if let server = mcpServer {
            await server.stop()
        }
        mcpServer = nil
        mcpTransport = nil
        mcpServerRunning = false
        mcpServerStatusDescription = "Stopped"
    }

    func restartMCPServer() async {
        await stopMCPServer()
        await startMCPServer()
    }

    func configureMCPConnector() {
        mcpConnector.setStateHandler { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleMCPStateChange(state)
            }
        }

        mcpConnector.setCallHandler { [weak self] entry in
            Task { @MainActor [weak self] in
                self?.appendServerCall(entry)
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

    private func configureMCPHandlers(_ server: Server) async {
        let toolsSnapshot = toolDefinitions.map(makeMCPTool)

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: toolsSnapshot)
        }

        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else { return .init(content: [.text("Server unavailable")], isError: true) }

            let arguments = Self.jsonArguments(from: params.arguments)
            let result = await self.callTool(MCPToolCall(name: params.name, arguments: arguments))
            switch result {
            case .success(let value):
                return .init(content: [.text(Self.jsonText(from: value))], structuredContent: nil, isError: false)
            case .failure(let error):
                return .init(content: [.text(error.localizedDescription)], structuredContent: nil, isError: true)
            }
        }
    }

    private func makeMCPTool(_ definition: MCPToolDefinition) -> Tool {
        let schema = JSONValue.object(definition.inputSchema)
        return Tool(
            name: definition.name,
            title: nil,
            description: definition.description,
            inputSchema: Self.mcpValue(from: schema),
            annotations: nil,
            outputSchema: nil,
            icons: nil,
            _meta: nil
        )
    }

    nonisolated private static func jsonArguments(from value: [String: Value]?) -> [String: JSONValue] {
        guard let value else { return [:] }
        guard
            let data = try? JSONEncoder().encode(value),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object.compactMapValues { JSONValue.from(any: $0) }
    }

    nonisolated private static func mcpValue(from value: JSONValue) -> Value {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        if
            let data = try? encoder.encode(value),
            let decoded = try? decoder.decode(Value.self, from: data)
        {
            return decoded
        }
        return .null
    }

    nonisolated private static func jsonText(from value: JSONValue) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
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
                name: "list_unread_chats",
                description: "Lists mapped chats that have unread messages.",
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
                        "text": .object(["type": .string("string")]),
                        "messages": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")])
                        ])
                    ]),
                    "required": .array([.string("chatId")])
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
            ),
            MCPToolDefinition(
                name: "get_instructions",
                description: "Returns the assistant instructions configured in the app.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([:])
                ]
            ),
            MCPToolDefinition(
                name: "speak",
                description: "Speaks a message out loud using text-to-speech.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "text": .object(["type": .string("string")]),
                        "language": .object(["type": .string("string")]),
                        "voiceIdentifier": .object(["type": .string("string")]),
                        "rate": .object(["type": .string("number")])
                    ]),
                    "required": .array([.string("text")])
                ]
            ),
            MCPToolDefinition(
                name: "ask_user",
                description: "Asks the user out loud and waits for a spoken response.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "prompt": .object(["type": .string("string")]),
                        "language": .object(["type": .string("string")]),
                        "voiceIdentifier": .object(["type": .string("string")]),
                        "recognitionLocale": .object(["type": .string("string")]),
                        "timeoutSeconds": .object(["type": .string("number")])
                    ]),
                    "required": .array([.string("prompt")])
                ]
            )
        ]
    }

    private func callTool(_ call: MCPToolCall) async -> Result<JSONValue, Error> {
        switch call.name {
        case "list_chats":
            let chats = memoryStore.conversations
                .filter { !isBlocked($0.name) }
                .map(conversationJSONValue)
            return .success(.object(["chats": .array(chats)]))
        case "list_unread_chats":
            let chats = memoryStore.conversations
                .filter { !isBlocked($0.name) }
                .filter { $0.unreadCount > 0 }
                .map(conversationJSONValue)
            return .success(.object(["chats": .array(chats)]))
        case "get_recent_messages":
            guard let chatId = call.arguments["chatId"]?.stringValue ?? call.arguments["chat_id"]?.stringValue else {
                return .failure(MCPServerError.missingParameter("chatId"))
            }

            let limit = max(1, call.arguments["limit"]?.intValue ?? 10)
            if let conversation = memoryStore.conversation(for: chatId), isBlocked(conversation.name) {
                return .failure(MCPServerError.invalidRequest)
            }
            if memoryStore.chatState(for: chatId) == nil {
                await ensureChatLoaded(chatId: chatId, reason: "get_recent_messages")
            }

            guard let chatState = memoryStore.chatState(for: chatId) else {
                return .success(.object(["chat": .null, "messages": .array([])]))
            }

            let messages = chatState.messages.suffix(limit).map(messageJSONValue)
            return .success(.object([
                "chat": conversationJSONValue(chatState.chat),
                "messages": .array(messages)
            ]))
        case "send_message":
            guard let chatId = call.arguments["chatId"]?.stringValue ?? call.arguments["chat_id"]?.stringValue else {
                return .failure(MCPServerError.missingParameter("chatId"))
            }

            let singleText = call.arguments["text"]?.stringValue
            let messageArray: [String]? = {
                guard case .array(let values) = call.arguments["messages"] else { return nil }
                return values.compactMap { $0.stringValue }
            }()

            let texts: [String]
            if let messageArray, !messageArray.isEmpty {
                texts = messageArray
            } else if let singleText {
                texts = [singleText]
            } else {
                return .failure(MCPServerError.missingParameter("text"))
            }

            do {
                var results: [JSONValue] = []
                for text in texts {
                    let prefixedText = applyMCPSendMessagePrefixIfNeeded(text)
                    try await sendMessageViaScheduler(prefixedText, to: chatId)
                    results.append(.object([
                        "ok": .bool(true),
                        "chatId": .string(chatId),
                        "text": .string(text)
                    ]))
                }
                return .success(.object([
                    "ok": .bool(true),
                    "chatId": .string(chatId),
                    "results": .array(results)
                ]))
            } catch {
                return .failure(error)
            }
        case "wait_for_message":
//            let timeoutSeconds = max(1, call.arguments["timeoutSeconds"]?.intValue ?? 60)
            let result = await memoryStore.waitForNextMessage(
                chatId: call.arguments["chatId"]?.stringValue ?? call.arguments["chat_id"]?.stringValue,
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
        case "get_instructions":
            return .success(.object(["instructions": .string(assistantInstructions)]))
        case "speak":
            guard let text = call.arguments["text"]?.stringValue else {
                return .failure(MCPServerError.missingParameter("text"))
            }

            let language = call.arguments["language"]?.stringValue ?? speechLanguage
            let voiceIdentifier = call.arguments["voiceIdentifier"]?.stringValue ?? speechVoiceIdentifier
            let rate = call.arguments["rate"].flatMap { value -> Float? in
                if case .number(let number) = value {
                    return Float(number)
                }
                return nil
            } ?? speechRate
            await voiceAssistant.speak(text, language: language, voiceIdentifier: voiceIdentifier, rate: rate)
            return .success(.object(["ok": .bool(true)]))
        case "ask_user":
            guard let prompt = call.arguments["prompt"]?.stringValue else {
                return .failure(MCPServerError.missingParameter("prompt"))
            }

            let language = call.arguments["language"]?.stringValue ?? speechLanguage
            let voiceIdentifier = call.arguments["voiceIdentifier"]?.stringValue ?? speechVoiceIdentifier
            let recognitionLocaleIdentifier = call.arguments["recognitionLocale"]?.stringValue ?? recognitionLocaleIdentifier
            let timeoutSeconds = max(3, call.arguments["timeoutSeconds"]?.intValue ?? 20)

            do {
                let transcript = try await voiceAssistant.askUser(
                    prompt: prompt,
                    language: language,
                    voiceIdentifier: voiceIdentifier,
                    recognitionLocaleIdentifier: recognitionLocaleIdentifier,
                    timeoutSeconds: timeoutSeconds
                )
                return .success(.object([
                    "timedOut": .bool(false),
                    "transcript": .string(transcript)
                ]))
            } catch let error as VoiceAssistantError {
                switch error {
                case .timedOut:
                    return .success(.object([
                        "timedOut": .bool(true),
                        "transcript": .null
                    ]))
                default:
                    return .failure(error)
                }
            } catch {
                return .failure(error)
            }
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
