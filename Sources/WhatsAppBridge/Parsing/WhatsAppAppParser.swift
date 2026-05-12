import Foundation

struct WhatsAppScreenState: Equatable {
    let conversations: [ConversationSummary]
    let selectedChatName: String?
    let messages: [Message]
    let composeFocused: Bool
    let canSendText: Bool
    let sendButtonPath: [Int]?
}

struct WhatsAppAppParser {
    private let conversationListParser = WhatsAppConversationListParser()
    private let currentConversationParser = WhatsAppCurrentConversationParser()

    func parse(snapshot: WhatsAppSnapshot, messageLimit: Int = 10) -> WhatsAppScreenState {
        let accessibilityObject = AccessibilityObject(root: snapshot.rootNode)
        let conversations = conversationListParser.parseConversations(from: accessibilityObject)
        let currentConversation = currentConversationParser.parse(
            from: accessibilityObject,
            selectedChatName: conversations.first(where: \.isSelected)?.name,
            limit: messageLimit
        )

        return WhatsAppScreenState(
            conversations: conversations,
            selectedChatName: currentConversation.selectedChatName,
            messages: currentConversation.messages,
            composeFocused: currentConversation.composeFocused,
            canSendText: currentConversation.canSendText,
            sendButtonPath: currentConversation.sendButtonPath
        )
    }

    func debugReport(snapshot: WhatsAppSnapshot) -> String {
        let accessibilityObject = AccessibilityObject(root: snapshot.rootNode)
        let root = accessibilityObject.root
        let flattened = root.flattened
        let nodesWithFrame = flattened.filter { $0.frame != nil }
        let nodesWithText = flattened.filter { !WhatsAppParserSupport.normalizedUniqueTexts($0.textFragments).isEmpty }
        let chatList = WhatsAppAccessibilityMap().chatList(in: root)
        let messageList = WhatsAppAccessibilityMap().messageList(in: root)
        let conversationCandidates = conversationListParser.conversationCandidates(from: accessibilityObject)
        let parsed = parse(snapshot: snapshot)

        let candidateLines = conversationCandidates.prefix(80).map { node in
            let frame = node.frame.map { "x:\(Int($0.minX)) y:\(Int($0.minY)) w:\(Int($0.width)) h:\(Int($0.height))" } ?? "no-frame"
            let path = node.accessibilityPath.map(String.init).joined(separator: ".")
            let texts = WhatsAppParserSupport.normalizedUniqueTexts(node.textFragments).prefix(8).joined(separator: " | ")
            return "- path=\(path) role=\(node.role ?? "nil") frame=(\(frame)) text=\(texts)"
        }

        let parsedLines = parsed.conversations.map { conversation in
            "- name=\(conversation.name) unread=\(conversation.unreadCount) date=\(conversation.lastMessageAtText ?? "nil") preview=\(conversation.lastMessagePreview ?? "nil") path=\(conversation.accessibilityPath.map(String.init).joined(separator: "."))"
        }

        return """
        WhatsApp parser debug:
          capturedAt: \(snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))
          rootFrame: \(root.frame.map { "x:\(Int($0.minX)) y:\(Int($0.minY)) w:\(Int($0.width)) h:\(Int($0.height))" } ?? "nil")
          allNodes: \(flattened.count)
          nodesWithFrame: \(nodesWithFrame.count)
          nodesWithText: \(nodesWithText.count)
          chatListPath: \(chatList?.accessibilityPath.map(String.init).joined(separator: ".") ?? "nil")
          messageListPath: \(messageList?.accessibilityPath.map(String.init).joined(separator: ".") ?? "nil")
          looseConversationCandidates: \(conversationCandidates.count)
          parsedConversations: \(parsed.conversations.count)

        Parsed conversations:
        \(parsedLines.isEmpty ? "- none" : parsedLines.joined(separator: "\n"))

        Loose conversation candidates:
        \(candidateLines.isEmpty ? "- none" : candidateLines.joined(separator: "\n"))
        """
    }
}
