import Foundation

struct ListNicknamesTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "list_nicknames",
        description: "Lists saved nicknames for WhatsApp chats. If a lookup term is provided, returns matching nicknames or falls back to the full list when nothing matches.",
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
        let chatId = arguments.string(for: "chatId", "chat_id")
        let lookupTerm = arguments.string(for: "nickname", "query")?.trimmingCharacters(in: .whitespacesAndNewlines)

        let allNicknames = await context.nicknamesRepository.list(chatId: chatId)

        guard let lookupTerm, !lookupTerm.isEmpty else {
            return .success(.object([
                "nicknames": .array(allNicknames.map(context.nicknameEntryJSONValue))
            ]))
        }

        let foundNicknames = await context.nicknamesRepository.list(
            chatId: chatId,
            nicknameQuery: lookupTerm
        )

        if !foundNicknames.isEmpty {
            return .success(.object([
                "foundNicknames": .array(foundNicknames.map(context.nicknameEntryJSONValue))
            ]))
        }

        return .success(.object([
            "message": .string("No nickname matched the provided lookup term. Returning the unfiltered nickname list as fallback."),
            "foundNicknames": .array([]),
            "allNicknames": .array(allNicknames.map(context.nicknameEntryJSONValue))
        ]))
    }
}
