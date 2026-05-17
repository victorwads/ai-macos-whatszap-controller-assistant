import Foundation

struct ListNicknamesTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "list_nicknames",
        description: "Lists saved nicknames for WhatsApp chats, optionally filtered by chat or nickname search.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "chatId": .object(["type": .string("string")]),
                "nickname": .object(["type": .string("string")]),
                "query": .object(["type": .string("string")])
            ])
        ],
        exampleParameters: [
            .init(name: "nickname", value: .string("Fred"))
        ],
        traits: [.readOnly]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let entries = await context.nicknamesRepository.list(
            chatId: arguments.string(for: "chatId", "chat_id"),
            nicknameQuery: arguments.string(for: "nickname", "query")
        )
        return .success(.object([
            "nicknames": .array(entries.map(context.nicknameEntryJSONValue))
        ]))
    }
}
