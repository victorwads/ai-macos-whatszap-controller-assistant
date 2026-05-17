import Foundation

extension AppModel {
    static var preview: AppModel {
        let model = AppModel(startupMode: .preview)
        model.seedPreviewData()
        return model
    }

    private func seedPreviewData() {
        logs = [
            LogEntry(level: .info, message: "Preview booted"),
            LogEntry(level: .warning, message: "Waiting for WhatsApp…"),
            LogEntry(level: .error, message: "Accessibility not granted (preview sample)")
        ]

        conversations = [
            ConversationSummary(
                id: "chat-1",
                accessibilityPath: [0, 1],
                name: "Family",
                unreadCount: 2,
                isPinned: true,
                isSelected: true,
                lastMessagePreview: "Ok, combinado.",
                lastMessageAtText: "09:41",
                lastMessageDirection: .incoming,
                lastMessageStatus: .delivered,
                isTyping: false
            ),
            ConversationSummary(
                id: "chat-2",
                accessibilityPath: [0, 2],
                name: "Work",
                unreadCount: 0,
                isPinned: false,
                isSelected: false,
                lastMessagePreview: "Can you review the PR?",
                lastMessageAtText: "Yesterday",
                lastMessageDirection: .outgoing,
                lastMessageStatus: .read,
                isTyping: true
            )
        ]

        selectedConversationId = conversations.first?.id
        selectedChatState = ChatState(
            chat: conversations[0],
            messages: [
                Message(
                    id: "m1",
                    chatId: "chat-1",
                    direction: .incoming,
                    kind: .text,
                    text: "Bom dia!",
                    durationSeconds: nil,
                    timestamp: Date().addingTimeInterval(-3600),
                    status: .delivered,
                    rawAccessibilityText: "Bom dia!",
                    handledAt: Date().addingTimeInterval(-3550)
                ),
                Message(
                    id: "m2",
                    chatId: "chat-1",
                    direction: .outgoing,
                    kind: .text,
                    text: "Bom dia :)",
                    durationSeconds: nil,
                    timestamp: Date().addingTimeInterval(-3500),
                    status: .read,
                    rawAccessibilityText: "Bom dia :)"
                )
            ],
            composeFocused: false,
            canSendText: true
        )

        serverCalls = [
            MCPServerCallEntry(
                durationMilliseconds: 42,
                requestMethod: "POST",
                requestPath: "/mcp",
                requestHeaders: ["content-type": "application/json"],
                requestBody: Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#.utf8),
                responseStatusCode: 200,
                responseHeaders: ["content-type": "application/json"],
                responseBody: Data(#"{"jsonrpc":"2.0","id":1,"result":{"tools":[]}}"#.utf8)
            ),
            MCPServerCallEntry(
                durationMilliseconds: 210,
                requestMethod: "POST",
                requestPath: "/mcp",
                requestHeaders: ["content-type": "application/json"],
                requestBody: Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_chats","arguments":{}}}"#.utf8),
                responseStatusCode: 500,
                responseHeaders: ["content-type": "application/json"],
                responseBody: Data(#"{"jsonrpc":"2.0","id":2,"error":{"message":"Preview sample error"}}"#.utf8)
            )
        ]

        pendingClientAskCount = 1
        pendingClientPromptWaitCount = 1
        mcpServerRunning = false
        mcpServerStatusDescription = "Stopped (preview)"
        mcpServerHost = "localhost"
        mcpServerPort = 8080
        mcpServerPortText = "8080"
        whatsAppWebAccounts = [
            WhatsAppWebAccount(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
                name: "Personal",
                profileIdentifier: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
                createdAt: Date().addingTimeInterval(-1200)
            )
        ]
        selectedWhatsAppWebAccountId = whatsAppWebAccounts.first?.id
    }
}
