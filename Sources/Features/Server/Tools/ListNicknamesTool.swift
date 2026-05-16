import Foundation

struct ListNicknamesTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "list_nicknames",
        description: "Lists saved nicknames for WhatsApp chats.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "chatId": .object(["type": .string("string")])
            ])
        ],
        exampleParameters: [
            .init(name: "chatId", value: .string("chat-1"))
        ],
        traits: [.readOnly]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let entries = await context.nicknamesRepository.list(chatId: arguments.string(for: "chatId", "chat_id"))
        return .success(.object([
            "nicknames": .array(entries.map(context.nicknameEntryJSONValue))
        ]))
    }
}
