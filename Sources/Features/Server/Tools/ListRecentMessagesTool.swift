import Foundation

struct ListRecentMessagesTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "list_recent_messages",
        description: "Lists recent messages for a mapped chat.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "chatId": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")])
            ]),
            "required": .array([.string("chatId")])
        ],
        exampleParameters: [
            .init(name: "chatId", value: .string("chat-1")),
            .init(name: "limit", value: .number(5))
        ],
        traits: [.readOnly]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let chatId = arguments.string(for: "chatId", "chat_id") else {
            return .failure(MCPServerError.missingParameter("chatId"))
        }

        let limit = max(1, arguments.int(for: "limit") ?? 10)
        let conversation = await MainActor.run { context.memoryStore.conversation(for: chatId) }
        if let conversation, await MainActor.run { context.isBlocked(conversation.name) } {
            return .failure(MCPServerError.invalidRequest)
        }
        let cachedChatState = await MainActor.run { context.memoryStore.chatState(for: chatId) }
        if cachedChatState == nil {
            await context.ensureChatLoaded(chatId, "list_recent_messages")
        }

        let chatState = await MainActor.run { context.memoryStore.chatState(for: chatId) }
        guard let chatState else {
            return .success(.object(["messages": .array([])]))
        }

        _ = await MainActor.run { context.memoryStore.consumeUnreadMessages(chatId: chatId) }
        let messages = await MainActor.run { context.memoryStore.recentMessages(chatId: chatId, limit: limit) }
            .map(context.messageJSONValue)
        return .success(.object([
            "chat": context.conversationJSONValue(chatState.chat),
            "messages": .array(messages)
        ]))
    }
}
