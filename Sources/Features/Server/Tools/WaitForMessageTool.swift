import Foundation

struct WaitForMessageTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "wait_for_chat_message",
        description: "Waits until unread messages appear for a specific WhatsApp chat or the client provides a prompt.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "chatId": .object(["type": .string("string")])
            ]),
            "required": .array([.string("chatId")])
        ],
        exampleParameters: [
            .init(name: "chatId", value: .string("chat-1"))
        ],
        traits: [.blocking]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let chatId = arguments.string(for: "chatId", "chat_id") else {
            return .failure(MCPServerError.missingParameter("chatId"))
        }

        let waitId = await context.beginClientPromptWait()
        defer {
            Task { await context.endClientPromptWait(id: waitId) }
        }

        while true {
            if Task.isCancelled {
                return .failure(CancellationError())
            }

            if let prompt = await context.consumeClientPrompt() {
                return .success(.object([
                    "timedOut": .bool(false),
                    "clientPrompt": .string(prompt)
                ]))
            }

            let consumed = await MainActor.run {
                context.memoryStore.consumeUnreadMessages(chatId: chatId)
            }
            if !consumed.isEmpty {
                let chat = await MainActor.run {
                    consumed.first.flatMap { message in
                        context.memoryStore.chatState(for: message.chatId)?.chat
                            ?? context.memoryStore.conversation(for: message.chatId)
                    }
                }

                guard let chat else {
                    return .success(
                        .object([
                            "timedOut": .bool(false),
                            "chat": .null,
                            "messages": .array(consumed.map(context.messageJSONValue))
                        ])
                        .pruningNulls()
                    )
                }

                return .success(
                    .object([
                        "timedOut": .bool(false),
                        "chat": context.conversationJSONValue(chat),
                        "messages": .array(consumed.map(context.messageJSONValue))
                    ])
                    .pruningNulls()
                )
            }

            try? await Task.sleep(for: .milliseconds(350))
        }
    }
}
