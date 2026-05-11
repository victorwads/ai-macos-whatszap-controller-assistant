import Foundation

struct WhatsAppCurrentConversationState: Equatable {
    let selectedChatName: String?
    let messages: [Message]
    let composeFocused: Bool
    let canSendText: Bool
    let sendButtonPath: [Int]?
}

struct WhatsAppCurrentConversationParser {
    private let accessibilityMap = WhatsAppAccessibilityMap()

    func parse(from accessibilityObject: AccessibilityObject, selectedChatName: String?, limit: Int) -> WhatsAppCurrentConversationState {
        WhatsAppCurrentConversationState(
            selectedChatName: selectedChatName,
            messages: parseMessages(from: accessibilityObject.root, selectedChatName: selectedChatName, limit: limit),
            composeFocused: accessibilityMap.composeField(in: accessibilityObject.root) != nil,
            canSendText: accessibilityObject.containsText(matching: ["send", "enviar"]),
            sendButtonPath: accessibilityMap.sendButton(in: accessibilityObject.root)?.accessibilityPath
        )
    }

    private func parseMessages(from root: RawAXNode, selectedChatName: String?, limit: Int) -> [Message] {
        let candidates = accessibilityMap.messageList(in: root)?.children.filter(isMessageRow(_:)) ?? []

        var seen = Set<String>()
        let messages = candidates.compactMap { node -> Message? in
            let parsedMessage = parseMessageDescription(node.nodeDescription)
            guard let rawText = parsedMessage.text else {
                return nil
            }

            let signature = "\(Int(node.frame?.minY ?? 0))|\(rawText)"
            guard !seen.contains(signature) else {
                return nil
            }
            seen.insert(signature)

            let chatId = selectedChatName.map(WhatsAppParserSupport.stableId(for:)) ?? "selected-chat"
            let rawAccessibilityText = WhatsAppParserSupport.normalizedUniqueTexts(node.textFragments).joined(separator: " | ")

            return Message(
                id: WhatsAppParserSupport.stableId(for: signature),
                chatId: chatId,
                direction: parsedMessage.direction,
                kind: parsedMessage.kind,
                text: rawText,
                durationSeconds: nil,
                timestamp: nil,
                status: parsedMessage.status,
                rawAccessibilityText: rawAccessibilityText
            )
        }

        return Array(messages.suffix(limit))
    }

    private func isMessageRow(_ node: RawAXNode) -> Bool {
        guard node.role == "AXStaticText" else {
            return false
        }

        let text = [node.nodeDescription, node.help, node.stringValue]
            .compactMap { $0 }
            .joined(separator: " ")

        return text.contains("Sent to")
            || text.contains("Received from")
            || text.contains("Voice message")
            || text.contains("Your message")
            || text.contains("message,")
    }

    private func parseMessageDescription(_ description: String?) -> (text: String?, direction: MessageDirection, kind: MessageKind, status: MessageStatus) {
        let tokens = WhatsAppParserSupport.axTokens(description)
        guard let first = tokens.first else {
            return (nil, .unknown, .unknown, .unknown)
        }

        let combined = tokens.joined(separator: " ").lowercased()
        let direction = WhatsAppParserSupport.messageDirection(in: combined)
        let kind = WhatsAppParserSupport.messageKind(in: combined)
        let status = WhatsAppParserSupport.messageStatus(in: combined)
        let metadataIndex = tokens.firstIndex(where: WhatsAppParserSupport.isMessageMetadata(_:)) ?? tokens.count

        if first.lowercased().contains("voice message") {
            return ("Voice message", direction, .voice, status)
        }

        let messageStart = first.lowercased().contains("your message") || first.lowercased() == "message" ? 1 : 0
        let messageTokens = messageStart < metadataIndex ? Array(tokens[messageStart..<metadataIndex]) : []
        let messageText = messageTokens.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)

        return (messageText.isEmpty ? first : messageText, direction, kind, status)
    }
}
