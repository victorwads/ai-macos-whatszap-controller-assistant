import Foundation

struct SendMessageTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "send_message",
        description: "Sends a message to a mapped chat through Accessibility.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "chatId": .object(["type": .string("string")]),
                "messages": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ])
            ]),
            "required": .array([.string("chatId"), .string("messages")])
        ],
        exampleParameters: [
            .init(name: "chatId", value: .string("chat-1")),
            .init(name: "messages", value: .array([
                .string("Testing send_message from the tools browser."),
                .string("Another batch message"),
            ]))
        ],
        traits: [.writesState, .sideEffect]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let chatId = arguments.string(for: "chatId", "chat_id") else {
            return .failure(MCPServerError.missingParameter("chatId"))
        }

        let texts = parseMessages(from: arguments)
        guard !texts.isEmpty else {
            return .failure(MCPServerError.missingParameter("messages"))
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

    private static func parseMessages(from arguments: MCPToolArguments) -> [String] {
        if let messageArray = arguments.stringArray(for: "messages") {
            return messageArray.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }

        guard let raw = arguments.string(for: "messages") else {
            return []
        }

        return raw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
