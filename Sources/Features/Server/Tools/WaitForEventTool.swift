import Foundation

struct WaitForEventTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "wait_for_event",
        description: "Waits until any unread WhatsApp messages are available or the client provides a prompt. Returns lightweight chat identifiers for affected chats.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([:])
        ],
        exampleParameters: [],
        traits: [.blocking]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
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
                    "events": .array([
                        .object([
                            "type": .string("client_prompt"),
                            "prompt": .string(prompt)
                        ])
                    ])
                ]))
            }

            let consumed = await MainActor.run {
                context.memoryStore.consumeUnreadMessages(chatId: nil)
            }
            if !consumed.isEmpty {
                let grouped = Dictionary(grouping: consumed, by: \.chatId)
                var events: [JSONValue] = []
                for chatId in grouped.keys.sorted() {
                    guard grouped[chatId]?.isEmpty == false else {
                        continue
                    }

                    let chat = await MainActor.run {
                        context.memoryStore.chatState(for: chatId)?.chat
                            ?? context.memoryStore.conversation(for: chatId)
                    }

                    if let chat {
                        events.append(.object([
                            "type": .string("chat_messages"),
                            "chat": .object([
                                "id": .string(chat.id),
                                "name": .string(chat.name)
                            ])
                        ]))
                    } else {
                        events.append(.object([
                            "type": .string("chat_messages"),
                            "chat": .null,
                            "chatId": .string(chatId)
                        ]))
                    }
                }

                return .success(.object([
                    "timedOut": .bool(false),
                    "events": .array(events)
                ]))
            }

            try? await Task.sleep(for: .milliseconds(350))
        }
    }
}
