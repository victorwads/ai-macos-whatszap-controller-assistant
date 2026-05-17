import Foundation

struct SaveNicknameTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "save_nickname",
        description: "Saves a nickname alias for a person or contact. The nickname and originalName are required. chatId is optional and only links the alias to a specific WhatsApp chat when available.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "nickname": .object(["type": .string("string")]),
                "originalName": .object(["type": .string("string")]),
                "chatId": .object(["type": .string("string")])
            ]),
            "required": .array([.string("nickname"), .string("originalName")])
        ],
        exampleParameters: [
            .init(name: "nickname", value: .string("Wades")),
            .init(name: "originalName", value: .string("Victor"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let chatId = arguments.string(for: "chatId", "chat_id")
        let originalName = arguments.string(for: "originalName")

        do {
            let result = try await context.nicknamesRepository.save(
                originalName: originalName,
                chatId: chatId,
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
