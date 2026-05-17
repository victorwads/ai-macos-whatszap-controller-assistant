import Foundation
import WebKit

@MainActor
final class WebProvider: WhatsAppIntegrationProvider {
    let kind: WhatsAppIntegrationMode = .web

    let parser: WhatsAppConversationParser
    let interactor: WhatsAppConversationInteractor

    init(
        accountId: UUID,
        accounts: @escaping () -> [WhatsAppWebAccount],
        sessionStore: WhatsAppWebSessionStore,
        bridge: WhatsAppWebBridge
    ) {
        self.parser = WebParser(accountId: accountId, accounts: accounts, sessionStore: sessionStore, bridge: bridge)
        self.interactor = WebInteractor(accountId: accountId, accounts: accounts, sessionStore: sessionStore, bridge: bridge)
    }
}

@MainActor
private struct WebParser: WhatsAppConversationParser {
    let accountId: UUID
    let accounts: () -> [WhatsAppWebAccount]
    let sessionStore: WhatsAppWebSessionStore
    let bridge: WhatsAppWebBridge

    func listConversations() async throws -> [ConversationSummary] {
        guard let account = accounts().first(where: { $0.id == accountId }) else {
            return []
        }
        let webView = sessionStore.webView(for: account)
        let items = try await bridge.listChatTitles(from: webView, limit: 50)

        return items.map { item in
            ConversationSummary(
                id: "web:\(accountId.uuidString):\(item.title)",
                accessibilityPath: [],
                name: item.title,
                unreadCount: item.unreadCount ?? 0,
                isPinned: false,
                isSelected: false,
                lastMessagePreview: item.preview,
                lastMessageAtText: item.timeText,
                lastMessageDirection: .unknown,
                lastMessageStatus: .unknown,
                isTyping: false
            )
        }
    }

    func readMessages(limit: Int) async throws -> (selectedChatName: String?, messages: [Message], composeFocused: Bool, canSendText: Bool) {
        guard let account = accounts().first(where: { $0.id == accountId }) else {
            return (nil, [], false, false)
        }
        let webView = sessionStore.webView(for: account)
        let capture = try await bridge.captureSelectedChat(from: webView, limit: limit)

        let title = capture.selectedChatTitle
        let chatId = title.map { "web:\(accountId.uuidString):\($0)" } ?? "web:\(accountId.uuidString):unknown"
        let messages: [Message] = capture.messages.map { captured in
            let normalizedText = captured.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let ts = captured.timestampText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let id = "\(chatId)|\(captured.direction.rawValue)|text|\(normalizedText)|\(ts)"

            let status: MessageStatus = {
                switch captured.statusTestId {
                case "msg-check":
                    return .sent
                case "msg-dblcheck":
                    return .delivered
                default:
                    return .unknown
                }
            }()

            return Message(
                id: id,
                chatId: chatId,
                direction: captured.direction,
                kind: .text,
                authorName: captured.authorName,
                origin: .unknown,
                text: captured.text,
                durationSeconds: nil,
                timestamp: nil,
                status: status,
                rawAccessibilityText: captured.text,
                whatsappTimestampText: captured.timestampText
            )
        }

        return (title, messages, capture.flow == .chatSelected, capture.flow == .chatSelected)
    }
}

@MainActor
private struct WebInteractor: WhatsAppConversationInteractor {
    let accountId: UUID
    let accounts: () -> [WhatsAppWebAccount]
    let sessionStore: WhatsAppWebSessionStore
    let bridge: WhatsAppWebBridge

    func openConversation(_ conversation: ConversationSummary) async throws {
        guard let account = accounts().first(where: { $0.id == accountId }) else {
            return
        }
        let webView = sessionStore.webView(for: account)
        let targetKey = WhatsAppParserSupport.chatNameComparisonKey(conversation.name)

        var lastSnapshot: WhatsAppWebPageSnapshot?

        for attempt in 1...3 {
            try await bridge.openChatByTitle(from: webView, title: conversation.name)
            // WA Web can take a moment to swap the conversation pane and update the header.
            // Poll the header for up to ~2s before retrying the click.
            let start = Date()
            while Date().timeIntervalSince(start) < 2.0 {
                let snapshot = try await bridge.captureSnapshot(from: webView)
                lastSnapshot = snapshot
                let currentKey = WhatsAppParserSupport.chatNameComparisonKey(snapshot.selectedChatTitle)
                if snapshot.flow == .chatSelected, currentKey == targetKey {
                    return
                }
                try await Task.sleep(for: .milliseconds(150))
            }

            _ = attempt
        }

        let lastFlow = lastSnapshot?.flow.rawValue ?? "nil"
        let lastTitle = lastSnapshot?.selectedChatTitle ?? "nil"
        throw WhatsAppWebBridgeError.elementNotFound(
            "WebInteractor.openConversation(title='\(conversation.name)') could not confirm chat selection after retries. lastFlow=\(lastFlow) lastTitle=\(lastTitle)"
        )
    }
}
