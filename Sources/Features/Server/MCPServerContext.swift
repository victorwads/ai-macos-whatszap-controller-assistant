import Foundation

@MainActor
struct MCPServerContext {
    let runtime: any MCPServerRuntimeProviding
    let memoryStore: WhatsAppMemoryStore
    let accessibility: AccessibilityService
    let accessibilityScheduler: AccessibilityActionScheduler
    let parser: WhatsAppAppParser
    let interactor: WhatsAppInteractor
    let voiceAssistant: VoiceAssistant
    let nicknamesRepository: NicknamesRepository
    let memoriesRepository: MemoriesRepository
    let subjectsRepository: SubjectsRepository
    let clientVoiceEventsRepository: ClientVoiceEventsRepository
}

extension MCPServerContext {
    func assistantName() -> String {
        runtime.assistantName()
    }

    func speechLanguage() -> String {
        runtime.speechLanguage()
    }

    func speechVoiceIdentifier() -> String? {
        runtime.speechVoiceIdentifier()
    }

    func speechRate() -> Float {
        runtime.speechRate()
    }

    func formattedMCPSendMessages(for texts: [String]) -> [String] {
        runtime.formattedMCPSendMessages(for: texts)
    }

    func refreshPendingClientAskCount() async {
        await runtime.refreshPendingClientAskCount()
    }

    func beginClientPromptWait() async -> UUID {
        await runtime.beginClientPromptWait()
    }

    func endClientPromptWait(id: UUID) async {
        await runtime.endClientPromptWait(id: id)
    }

    func pendingClientPromptWaitCount() async -> Int {
        await runtime.pendingClientPromptWaitCount()
    }

    func submitClientPrompt(_ text: String) async {
        await runtime.submitClientPrompt(text)
    }

    func consumeClientPrompt() async -> String? {
        await runtime.consumeClientPrompt()
    }

    func sendMessageViaScheduler(_ text: String, _ conversationId: String) async throws {
        try await runtime.sendMessageViaScheduler(text, to: conversationId)
    }

    func sendMessagesViaScheduler(_ texts: [String], _ conversationId: String) async throws {
        try await runtime.sendMessagesViaScheduler(texts, to: conversationId)
    }

    func ensureChatLoaded(_ chatId: String, _ reason: String) async {
        await runtime.ensureChatLoaded(chatId: chatId, reason: reason)
    }

    func isBlocked(_ conversationName: String) -> Bool {
        runtime.isBlocked(conversationName)
    }

    func appendLog(_ message: String, level: LogLevel) {
        runtime.appendLog(message, level: level)
    }

    func conversationJSONValue(_ conversation: ConversationSummary) -> JSONValue {
        .object([
            "id": .string(conversation.id),
            "name": .string(conversation.name),
            "unreadCount": .number(Double(conversation.unreadCount)),
            "lastMessagePreview": conversation.lastMessagePreview.map(JSONValue.string) ?? .null,
            "lastMessageAtText": conversation.lastMessageAtText.map(JSONValue.string) ?? .null,
            "lastMessageDirection": .string(conversation.lastMessageDirection.rawValue),
            "lastMessageStatus": .string(conversation.lastMessageStatus.rawValue),
            "isTyping": .bool(conversation.isTyping)
        ])
    }

    func messageJSONValue(_ message: Message) -> JSONValue {
        .object([
            "id": .string(message.id),
            "chatId": .string(message.chatId),
            "direction": .string(message.direction.rawValue),
            "kind": .string(message.kind.rawValue),
            "text": message.text.map(JSONValue.string) ?? .null,
            "durationSeconds": message.durationSeconds.map(JSONValue.number) ?? .null,
            "timestamp": .from(date: message.timestamp),
            "status": .string(message.status.rawValue),
            "rawAccessibilityText": .string(message.rawAccessibilityText),
            "whatsappTimestampText": message.whatsappTimestampText.map(JSONValue.string) ?? .null,
            "ingestedAt": .from(date: message.ingestedAt),
            "handledAt": .from(date: message.handledAt),
            "isHandled": .bool(message.isHandled)
        ])
    }

    func chatMessagesEventJSONValue(chat: ConversationSummary, messages: [Message]) -> JSONValue {
        .object([
            "type": .string("chat_messages"),
            "chat": conversationJSONValue(chat),
            "messages": .array(messages.map(messageJSONValue))
        ])
    }

    func memoryEntryJSONValue(_ entry: MemoryEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "key": .string(entry.key),
            "content": .string(entry.content),
            "tags": .array(entry.tags.map(JSONValue.string)),
            "createdAt": .from(date: entry.createdAt),
            "updatedAt": .from(date: entry.updatedAt)
        ])
    }

    func subjectEntryJSONValue(_ entry: SubjectEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "title": .string(entry.title),
            "summary": .string(entry.summary),
            "initialRequest": .string(entry.initialRequest),
            "details": entry.details.map(JSONValue.string) ?? .null,
            "status": .string(entry.status.rawValue),
            "priority": .number(Double(entry.priority)),
            "participants": .array(entry.participants.map(JSONValue.string)),
            "nextSteps": .array(entry.nextSteps.map(JSONValue.string)),
            "eventLog": .array(entry.eventLog.map { event in
                .object([
                    "id": .string(event.id.uuidString),
                    "timestamp": .from(date: event.timestamp),
                    "description": .string(event.description),
                    "source": event.source.map(JSONValue.string) ?? .null,
                    "author": event.author.map(JSONValue.string) ?? .null
                ])
            }),
            "whatsappChatId": entry.whatsappChatId.map(JSONValue.string) ?? .null,
            "whatsappAfterMessageId": entry.whatsappAfterMessageId.map(JSONValue.string) ?? .null,
            "gmailThreadId": entry.gmailThreadId.map(JSONValue.string) ?? .null,
            "calendarEventId": entry.calendarEventId.map(JSONValue.string) ?? .null,
            "createdAt": .from(date: entry.createdAt),
            "updatedAt": .from(date: entry.updatedAt)
        ])
    }

    func nicknameEntryJSONValue(_ entry: NicknameEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "chatId": .string(entry.chatId),
            "chatName": .string(entry.chatName),
            "nickname": .string(entry.nickname),
            "createdAt": .from(date: entry.createdAt)
        ])
    }

    func eventEntries(from values: [JSONValue]?) -> [EventEntry]? {
        guard let values else { return nil }
        return values.compactMap { eventLogEntry in
            guard let eventObj = eventLogEntry.objectValue else { return nil }
            let desc = eventObj["description"]?.stringValue ?? ""
            let source = eventObj["source"]?.stringValue
            let author = eventObj["author"]?.stringValue
            let timestampStr = eventObj["timestamp"]?.stringValue
            let timestamp: Date = {
                if let iso = ISO8601DateFormatter().date(from: timestampStr ?? "") {
                    return iso
                }
                if let sec = eventObj["timestamp"]?.numberValue {
                    return Date(timeIntervalSince1970: sec)
                }
                return Date()
            }()
            return EventEntry(timestamp: timestamp, description: desc, source: source, author: author)
        }
    }
}
