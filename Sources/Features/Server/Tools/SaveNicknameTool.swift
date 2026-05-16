import Foundation

struct SaveNicknameTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
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
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let chatId = arguments.string(for: "chatId", "chat_id")
        let providedChatName = arguments.string(for: "chatName", "chat_name")
        let resolvedChatName = providedChatName ?? context.memoryStore.conversation(for: chatId ?? "")?.name

        do {
            let result = try await context.nicknamesRepository.save(
                chatId: chatId,
                chatName: resolvedChatName,
                nickname: arguments.string(for: "nickname")
            )
            return .success(.object([
                "ok": .bool(true),
                "created": .bool(result.created),
                "entry": context.nicknameEntryJSONValue(result.entry)
            ]))
        } catch {
            return .failure(error)
        }
    }
}
