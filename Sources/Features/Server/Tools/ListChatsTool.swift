import Foundation

struct ListChatsTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "list_chats",
        description: "Lists relevant chats from WhatsApp.",
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
            .map(context.conversationJSONValue)
        return .success(.object(["chats": .array(chats)]))
    }
}
