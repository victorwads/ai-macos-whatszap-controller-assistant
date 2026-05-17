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
    let sensitiveDataRepository: SensitiveDataRepository
    let subjectsRepository: SubjectsRepository
    let clientVoiceEventsRepository: ClientVoiceEventsRepository
}

extension MCPServerContext {
    func validatedSubjectId(_ subjectId: String?) async throws -> String {
        let trimmed = (subjectId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw SubjectsRepositoryError.missingParameter("subjectId")
        }

        guard let uuid = UUID(uuidString: trimmed) else {
            throw SubjectsRepositoryError.invalidParameter("Invalid subjectId")
        }

        _ = try await subjectsRepository.get(id: uuid)
        return trimmed
    }

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
            "lastMessagePreview": .nonEmptyString(conversation.lastMessagePreview),
            "lastMessageAtText": .nonEmptyString(conversation.lastMessageAtText),
            "lastMessageDirection": .string(conversation.lastMessageDirection.mcpValue),
            "lastMessageStatus": .string(conversation.lastMessageStatus.rawValue),
            "isTyping": .bool(conversation.isTyping)
        ])
        .pruningNulls()
    }

    func messageJSONValue(_ message: Message) -> JSONValue {
        .object([
            "id": .string(message.id),
            "direction": .string(message.direction.mcpValue),
            "kind": .string(message.kind.rawValue),
            "text": .nonEmptyString(message.text),
            "durationSeconds": .optionalNumber(message.durationSeconds),
            "timestamp": .from(date: message.timestamp),
            "status": .string(message.status.rawValue),
            "rawAccessibilityText": .string(message.rawAccessibilityText),
            "whatsappTimestampText": .nonEmptyString(message.whatsappTimestampText),
            "isHandled": .bool(message.isHandled)
        ])
        .pruningNulls()
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
            "key": .string(entry.key),
            "content": .string(entry.content)
        ])
        .pruningNulls()
    }

    func memorySearchResultJSONValue(_ result: MemorySearchResult) -> JSONValue {
        .object([
            "score": .number(result.score),
            "entry": memoryEntryJSONValue(result.entry)
        ])
        .pruningNulls()
    }

    func sensitiveDataUsageJSONValue(_ entry: SensitiveDataUsageEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "timestamp": .from(date: entry.timestamp),
            "chatId": .string(entry.chatId),
            "subjectId": .nonEmptyString(entry.subjectId),
            "subjectTitle": .nonEmptyString(entry.subjectTitle),
            "purpose": .string(entry.purpose)
        ])
        .pruningNulls()
    }

    func sensitiveDataSummaryJSONValue(_ entry: SensitiveDataEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "key": .string(entry.key),
            "label": .string(entry.label),
            "kind": .string(entry.kind),
            "valuePreview": .string(entry.maskedValue),
            "allowedChats": .array(entry.allowedChats.map(JSONValue.string)),
            "usageCount": .number(Double(entry.usageHistory.count)),
            "lastUsedAt": .from(date: entry.lastUsedAt),
            "createdAt": .from(date: entry.createdAt),
            "updatedAt": .from(date: entry.updatedAt)
        ])
        .pruningNulls()
    }

    func sensitiveDataAuditJSONValue(_ entry: SensitiveDataAuditEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "timestamp": .from(date: entry.timestamp),
            "action": .string(entry.action.rawValue),
            "subjectId": .string(entry.subjectId),
            "reason": .string(entry.reason),
            "key": .nonEmptyString(entry.key),
            "entryId": .nonEmptyString(entry.entryId?.uuidString),
            "query": .nonEmptyString(entry.query),
            "matchedCount": .optionalNumber(entry.matchedCount.map(Double.init))
        ])
        .pruningNulls()
    }

    func sensitiveDataEntryJSONValue(_ entry: SensitiveDataEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "key": .string(entry.key),
            "label": .string(entry.label),
            "kind": .string(entry.kind),
            "value": .string(entry.value),
            "valuePreview": .string(entry.maskedValue),
            "allowedChats": .array(entry.allowedChats.map(JSONValue.string)),
            "usageHistory": .array(entry.usageHistory.map(sensitiveDataUsageJSONValue)),
            "usageCount": .number(Double(entry.usageHistory.count)),
            "lastUsedAt": .from(date: entry.lastUsedAt),
            "createdAt": .from(date: entry.createdAt),
            "updatedAt": .from(date: entry.updatedAt)
        ])
        .pruningNulls()
    }

    func subjectEntryJSONValue(_ entry: SubjectEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "title": .string(entry.title),
            "summary": .string(entry.summary),
            "initialRequest": .string(entry.initialRequest),
            "stopCondition": .string(entry.stopCondition),
            "details": .nonEmptyString(entry.details),
            "status": .string(entry.status.rawValue),
            "priority": .number(Double(entry.priority)),
            "participants": .array(entry.participants.map(JSONValue.string)),
            "nextSteps": .array(entry.nextSteps.map(JSONValue.string)),
            "updatesLog": .array(entry.eventLog.map { .string($0.description) }),
            "whatsappChatId": .nonEmptyString(entry.whatsappChatId),
            "whatsappAfterMessageId": .nonEmptyString(entry.whatsappAfterMessageId),
            "gmailThreadId": .nonEmptyString(entry.gmailThreadId),
            "calendarEventId": .nonEmptyString(entry.calendarEventId),
            "createdAt": .from(date: entry.createdAt)
        ])
        .pruningNulls()
    }

    func nicknameEntryJSONValue(_ entry: NicknameEntry) -> JSONValue {
        .object([
            "id": .string(entry.id.uuidString),
            "originalName": .string(entry.originalName),
            "nickname": .string(entry.nickname),
            "chatId": .nonEmptyString(entry.chatId)
        ])
        .pruningNulls()
    }

}

private extension MessageDirection {
    var mcpValue: String {
        switch self {
        case .outgoing:
            return "sent"
        case .incoming:
            return "received"
        case .unknown:
            return "unknown"
        }
    }
}
