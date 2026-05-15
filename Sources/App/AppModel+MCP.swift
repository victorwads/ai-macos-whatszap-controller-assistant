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
                        "afterMessageId": .object(["type": .string("string")])
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
                name: "speak_to_client",
                description: "Speaks a message out loud to the client using text-to-speech.",
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
                name: "ask_to_client",
                description: "Asks the client out loud and waits for a spoken response.",
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
            ),
            MCPToolDefinition(
                name: "create_memory",
                description: "Creates a new long-term memory entry.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "title": .object(["type": .string("string")]),
                        "content": .object(["type": .string("string")]),
                        "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
                    ]),
                    "required": .array([.string("title"), .string("content")])
                ]
            ),
            MCPToolDefinition(
                name: "list_memories",
                description: "Lists memory entries.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([:])
                ]
            ),
            MCPToolDefinition(
                name: "delete_memory",
                description: "Deletes a memory entry by id.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("id")])
                ]
            ),
            MCPToolDefinition(
                name: "create_subject",
                description: "Creates a new operational subject to track until resolution.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "title": .object(["type": .string("string")]),
                        "details": .object(["type": .string("string")]),
                        "priority": .object(["type": .string("number")]),
                        "participants": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                        "nextSteps": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                        "whatsappChatId": .object(["type": .string("string")]),
                        "gmailThreadId": .object(["type": .string("string")]),
                        "calendarEventId": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("title")])
                ]
            ),
            MCPToolDefinition(
                name: "update_subject",
                description: "Updates an operational subject by id.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string")]),
                        "title": .object(["type": .string("string")]),
                        "details": .object(["type": .string("string")]),
                        "status": .object(["type": .string("string")]),
                        "priority": .object(["type": .string("number")]),
                        "participants": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                        "nextSteps": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                        "whatsappChatId": .object(["type": .string("string")]),
                        "whatsappAfterMessageId": .object(["type": .string("string")]),
                        "gmailThreadId": .object(["type": .string("string")]),
                        "calendarEventId": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("id")])
                ]
            ),
            MCPToolDefinition(
                name: "finish_subject",
                description: "Marks a subject as finished by id.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("id")])
                ]
            ),
            MCPToolDefinition(
                name: "list_active_subjects",
                description: "Lists active subjects.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([:])
                ]
            ),
            MCPToolDefinition(
                name: "get_subject",
                description: "Fetches a subject by id.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("id")])
                ]
            ),
            MCPToolDefinition(
                name: "delete_subject",
                description: "Deletes a subject by id.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("id")])
                ]
            ),
            MCPToolDefinition(
                name: "list_nicknames",
                description: "Lists saved nicknames for WhatsApp chats.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "chatId": .object(["type": .string("string")])
                    ])
                ]
            ),
            MCPToolDefinition(
                name: "save_nickname",
                description: "Saves a nickname for a WhatsApp chat (dedupes exact matches).",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "chatId": .object(["type": .string("string")]),
                        "chatName": .object(["type": .string("string")]),
                        "nickname": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("chatId"), .string("nickname")])
                ]
            ),
            MCPToolDefinition(
                name: "delete_nickname",
                description: "Deletes a saved nickname by id.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("id")])
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
            // The MCP client/tooling may enforce its own call timeout (~120s). To preserve the
            // "no timeout" semantics at the workflow level, we long-poll in chunks and let the
            // caller re-issue wait_for_message until it returns a message.
            let result = await memoryStore.waitForNextMessage(
                chatId: call.arguments["chatId"]?.stringValue ?? call.arguments["chat_id"]?.stringValue,
                afterMessageId: call.arguments["afterMessageId"]?.stringValue,
                timeoutSeconds: 110
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
        case "list_nicknames":
            let chatId = call.arguments["chatId"]?.stringValue ?? call.arguments["chat_id"]?.stringValue
            let entries = await nicknamesRepository.list(chatId: chatId)
            return .success(.object([
                "nicknames": .array(entries.map(nicknameEntryJSONValue))
            ]))
        case "save_nickname":
            let chatId = call.arguments["chatId"]?.stringValue ?? call.arguments["chat_id"]?.stringValue
            let nickname = call.arguments["nickname"]?.stringValue
            let providedChatName = call.arguments["chatName"]?.stringValue ?? call.arguments["chat_name"]?.stringValue
            let resolvedChatName = providedChatName ?? memoryStore.conversation(for: chatId ?? "")?.name

            do {
                let result = try await nicknamesRepository.save(
                    chatId: chatId,
                    chatName: resolvedChatName,
                    nickname: nickname
                )
                return .success(.object([
                    "ok": .bool(true),
                    "created": .bool(result.created),
                    "entry": nicknameEntryJSONValue(result.entry)
                ]))
            } catch {
                return .failure(error)
            }
        case "delete_nickname":
            let rawId = call.arguments["id"]?.stringValue
            guard let rawId, let id = UUID(uuidString: rawId) else {
                return .failure(NicknamesRepositoryError.invalidParameter("Invalid id"))
            }

            do {
                let deleted = try await nicknamesRepository.delete(id: id)
                return .success(.object([
                    "ok": .bool(true),
                    "deleted": .bool(deleted)
                ]))
            } catch {
                return .failure(error)
            }
        case "speak_to_client":
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
            _ = await clientVoiceEventsRepository.appendSpeak(text: text)
            await refreshPendingClientAskCount()
            await voiceAssistant.speak(text, language: language, voiceIdentifier: voiceIdentifier, rate: rate)
            return .success(.object(["ok": .bool(true)]))
        case "ask_to_client":
            guard let prompt = call.arguments["prompt"]?.stringValue else {
                return .failure(MCPServerError.missingParameter("prompt"))
            }

            let language = call.arguments["language"]?.stringValue ?? speechLanguage
            let voiceIdentifier = call.arguments["voiceIdentifier"]?.stringValue ?? speechVoiceIdentifier
            let recognitionLocaleIdentifier = call.arguments["recognitionLocale"]?.stringValue ?? recognitionLocaleIdentifier
            let timeoutSecondsRaw = call.arguments["timeoutSeconds"]?.intValue
            let timeoutSeconds: Int? = {
                guard let timeoutSecondsRaw else { return nil }
                return timeoutSecondsRaw > 0 ? timeoutSecondsRaw : nil
            }()
            let askEvent = await clientVoiceEventsRepository.appendAsk(prompt: prompt)
            await refreshPendingClientAskCount()

            do {
                let transcript = try await voiceAssistant.askUser(
                    prompt: prompt,
                    language: language,
                    voiceIdentifier: voiceIdentifier,
                    recognitionLocaleIdentifier: recognitionLocaleIdentifier,
                    timeoutSeconds: timeoutSeconds
                )
                _ = try? await clientVoiceEventsRepository.answerAsk(id: askEvent.id, transcript: transcript)
                await refreshPendingClientAskCount()
                return .success(.object([
                    "timedOut": .bool(false),
                    "transcript": .string(transcript)
                ]))
            } catch let error as VoiceAssistantError {
                switch error {
                case .timedOut:
                    await refreshPendingClientAskCount()
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
        case "create_memory":
            do {
                let entry = try await memoriesRepository.create(
                    title: call.arguments["title"]?.stringValue,
                    content: call.arguments["content"]?.stringValue,
                    tags: call.arguments["tags"]?.arrayValue?.compactMap(\.stringValue)
                )
                return .success(.object([
                    "ok": .bool(true),
                    "entry": memoryEntryJSONValue(entry)
                ]))
            } catch {
                return .failure(error)
            }
        case "list_memories":
            let entries = await memoriesRepository.list()
            return .success(.object([
                "entries": .array(entries.map(memoryEntryJSONValue))
            ]))
        case "delete_memory":
            let rawId = call.arguments["id"]?.stringValue
            guard let rawId, let id = UUID(uuidString: rawId) else {
                return .failure(MemoriesRepositoryError.invalidParameter("Invalid id"))
            }
            do {
                let deleted = try await memoriesRepository.delete(id: id)
                return .success(.object([
                    "ok": .bool(true),
                    "deleted": .bool(deleted)
                ]))
            } catch {
                return .failure(error)
            }
        case "create_subject":
            do {
                let entry = try await subjectsRepository.create(
                    title: call.arguments["title"]?.stringValue,
                    details: call.arguments["details"]?.stringValue,
                    priority: call.arguments["priority"]?.intValue,
                    participants: call.arguments["participants"]?.arrayValue?.compactMap(\.stringValue),
                    nextSteps: call.arguments["nextSteps"]?.arrayValue?.compactMap(\.stringValue),
                    whatsappChatId: call.arguments["whatsappChatId"]?.stringValue,
                    gmailThreadId: call.arguments["gmailThreadId"]?.stringValue,
                    calendarEventId: call.arguments["calendarEventId"]?.stringValue
                )
                return .success(.object([
                    "ok": .bool(true),
                    "entry": subjectEntryJSONValue(entry)
                ]))
            } catch {
                return .failure(error)
            }
        case "update_subject":
            let rawId = call.arguments["id"]?.stringValue
            guard let rawId, let id = UUID(uuidString: rawId) else {
                return .failure(SubjectsRepositoryError.invalidParameter("Invalid id"))
            }
            let status = call.arguments["status"]?.stringValue.flatMap(SubjectStatus.init(rawValue:))
            do {
                let entry = try await subjectsRepository.update(
                    id: id,
                    title: call.arguments["title"]?.stringValue,
                    details: call.arguments["details"]?.stringValue,
                    status: status,
                    priority: call.arguments["priority"]?.intValue,
                    participants: call.arguments["participants"]?.arrayValue?.compactMap(\.stringValue),
                    nextSteps: call.arguments["nextSteps"]?.arrayValue?.compactMap(\.stringValue),
                    whatsappChatId: call.arguments["whatsappChatId"]?.stringValue,
                    whatsappAfterMessageId: call.arguments["whatsappAfterMessageId"]?.stringValue,
                    gmailThreadId: call.arguments["gmailThreadId"]?.stringValue,
                    calendarEventId: call.arguments["calendarEventId"]?.stringValue
                )
                return .success(.object([
                    "ok": .bool(true),
                    "entry": subjectEntryJSONValue(entry)
                ]))
            } catch {
                return .failure(error)
            }
        case "finish_subject":
            let rawId = call.arguments["id"]?.stringValue
            guard let rawId, let id = UUID(uuidString: rawId) else {
                return .failure(SubjectsRepositoryError.invalidParameter("Invalid id"))
            }
            do {
                let entry = try await subjectsRepository.finish(id: id)
                return .success(.object([
                    "ok": .bool(true),
                    "entry": subjectEntryJSONValue(entry)
                ]))
            } catch {
                return .failure(error)
            }
        case "list_active_subjects":
            let entries = await subjectsRepository.listActive()
            return .success(.object([
                "entries": .array(entries.map(subjectEntryJSONValue))
            ]))
        case "get_subject":
            let rawId = call.arguments["id"]?.stringValue
            guard let rawId, let id = UUID(uuidString: rawId) else {
                return .failure(SubjectsRepositoryError.invalidParameter("Invalid id"))
            }
            do {
                let entry = try await subjectsRepository.get(id: id)
                return .success(.object([
                    "entry": subjectEntryJSONValue(entry)
                ]))
            } catch {
                return .failure(error)
            }
        case "delete_subject":
            let rawId = call.arguments["id"]?.stringValue
            guard let rawId, let id = UUID(uuidString: rawId) else {
                return .failure(SubjectsRepositoryError.invalidParameter("Invalid id"))
            }
            do {
                let deleted = try await subjectsRepository.delete(id: id)
                return .success(.object([
                    "ok": .bool(true),
                    "deleted": .bool(deleted)
                ]))
            } catch {
                return .failure(error)
            }
        default:
            return .failure(MCPServerError.invalidParameter("name"))
        }
    }

    private func memoryEntryJSONValue(_ entry: MemoryEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "title": .string(entry.title),
            "content": .string(entry.content),
            "tags": .array(entry.tags.map(JSONValue.string)),
            "createdAt": .from(date: entry.createdAt),
            "updatedAt": .from(date: entry.updatedAt)
        ])
    }

    private func subjectEntryJSONValue(_ entry: SubjectEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "title": .string(entry.title),
            "details": entry.details.map(JSONValue.string) ?? .null,
            "status": .string(entry.status.rawValue),
            "priority": .number(Double(entry.priority)),
            "participants": .array(entry.participants.map(JSONValue.string)),
            "nextSteps": .array(entry.nextSteps.map(JSONValue.string)),
            "whatsappChatId": entry.whatsappChatId.map(JSONValue.string) ?? .null,
            "whatsappAfterMessageId": entry.whatsappAfterMessageId.map(JSONValue.string) ?? .null,
            "gmailThreadId": entry.gmailThreadId.map(JSONValue.string) ?? .null,
            "calendarEventId": entry.calendarEventId.map(JSONValue.string) ?? .null,
            "createdAt": .from(date: entry.createdAt),
            "updatedAt": .from(date: entry.updatedAt)
        ])
    }

    private func nicknameEntryJSONValue(_ entry: NicknameEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "chatId": .string(entry.chatId),
            "chatName": .string(entry.chatName),
            "nickname": .string(entry.nickname),
            "createdAt": .from(date: entry.createdAt)
        ])
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
