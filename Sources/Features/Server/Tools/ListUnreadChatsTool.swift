import Foundation

struct ListUnreadChatsTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "list_unread_chats",
        description: "Lists mapped chats that have unread messages.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([:])
        ],
        exampleParameters: [],
        traits: [.readOnly]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let chats = context.memoryStore.conversations
            .filter { !context.isBlocked($0.name) }
            .filter { $0.unreadCount > 0 }
            .map(context.conversationJSONValue)
        return .success(.object(["chats": .array(chats)]))
    }
}
