import Foundation

struct WaitForMessageTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "wait_for_message",
        description: "Waits until a new message appears in memory and returns it.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "chatId": .object(["type": .string("string")]),
                "afterMessageId": .object(["type": .string("string")])
            ])
        ],
        exampleParameters: [
            .init(name: "chatId", value: .string("chat-1")),
            .init(name: "afterMessageId", value: .string("m2"))
        ],
        traits: [.blocking]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let result = await context.memoryStore.waitForNextMessage(
            chatId: arguments.string(for: "chatId", "chat_id"),
            afterMessageId: arguments.string(for: "afterMessageId", "after_message_id"),
            timeoutSeconds: 110
        )

        if let result {
            return .success(.object([
                "timedOut": .bool(false),
                "chat": context.conversationJSONValue(result.chat),
                "message": context.messageJSONValue(result.message)
            ]))
        }

        return .success(.object(["timedOut": .bool(true)]))
    }
}
