import Foundation

struct SendMessageTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "send_message",
        description: "Sends a message to a mapped chat through Accessibility.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "chatId": .object(["type": .string("string")]),
                "text": .object(["type": .string("string")]),
                "messages": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ])
            ]),
            "required": .array([.string("chatId")])
        ],
        exampleParameters: [
            .init(name: "chatId", value: .string("chat-1")),
            .init(name: "text", value: .string("Testing send_message from the tools browser.")),
            .init(name: "messages", value: .array([.string("Testing send_message from the tools browser.")]))
        ],
        traits: [.writesState, .sideEffect]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let chatId = arguments.string(for: "chatId", "chat_id") else {
            return .failure(MCPServerError.missingParameter("chatId"))
        }

        let texts: [String]
        if let messageArray = arguments.stringArray(for: "messages"), !messageArray.isEmpty {
            texts = messageArray
        } else if let singleText = arguments.string(for: "text") {
            texts = [singleText]
        } else {
            return .failure(MCPServerError.missingParameter("text"))
        }

        do {
            var results: [JSONValue] = []
            for text in texts {
                let prefixedText = context.applyMCPSendMessagePrefixIfNeeded(text)
                try await context.sendMessageViaScheduler(prefixedText, chatId)
                results.append(.object([
                    "ok": .bool(true),
                    "chatId": .string(chatId),
                    "text": .string(text)
                ]))
            }
            return .success(.object([
                "ok": .bool(true),
                "chatId": .string(chatId),
                "results": .array(results)
            ]))
        } catch {
            return .failure(error)
        }
    }
}
