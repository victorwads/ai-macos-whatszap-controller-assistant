import Foundation

struct GetRecentMessagesTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
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
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let chatId = arguments.string(for: "chatId", "chat_id") else {
            return .failure(MCPServerError.missingParameter("chatId"))
        }

        let limit = max(1, arguments.int(for: "limit") ?? 10)
        if let conversation = context.memoryStore.conversation(for: chatId), context.isBlocked(conversation.name) {
            return .failure(MCPServerError.invalidRequest)
        }
        if context.memoryStore.chatState(for: chatId) == nil {
            await context.ensureChatLoaded(chatId, "get_recent_messages")
        }

        guard let chatState = context.memoryStore.chatState(for: chatId) else {
            return .success(.object(["chat": .null, "messages": .array([])]))
        }

        let messages = chatState.messages.suffix(limit).map(context.messageJSONValue)
        return .success(.object([
            "chat": context.conversationJSONValue(chatState.chat),
            "messages": .array(messages)
        ]))
    }
}
