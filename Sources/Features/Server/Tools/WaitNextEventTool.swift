import Foundation

struct WaitNextEventTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "wait_for_event",
        description: "Waits until any unread WhatsApp messages are available or the client provides a prompt.",
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

        let deadline = Date().addingTimeInterval(110)

        while Date() < deadline {
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
                    guard let messages = grouped[chatId], !messages.isEmpty else {
                        continue
                    }

                    let chat = await MainActor.run {
                        context.memoryStore.chatState(for: chatId)?.chat
                            ?? context.memoryStore.conversation(for: chatId)
                    }

                    if let chat {
                        events.append(context.chatMessagesEventJSONValue(chat: chat, messages: messages))
                    } else {
                        events.append(.object([
                            "type": .string("chat_messages"),
                            "chat": .null,
                            "messages": .array(messages.map(context.messageJSONValue))
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

        return .success(.object([
            "timedOut": .bool(true),
            "events": .array([])
        ]))
    }
}
