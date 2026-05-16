import Foundation

struct WhatsAppConversationListParser {
    private let accessibilityMap = WhatsAppAccessibilityMap()

    func parseConversations(from accessibilityObject: AccessibilityObject) -> [ConversationSummary] {
        let root = accessibilityObject.root
        let candidates: [RawAXNode]
        if let chatList = accessibilityMap.chatList(in: root) {
            // WhatsApp often wraps each row in nested groups; scan descendants instead of only direct children.
            candidates = chatList.flattened.filter(isConversationRow(_:))
        } else {
            candidates = []
        }

        var seenIds = Set<String>()
        let conversations = candidates.compactMap { candidate -> ConversationSummary? in
            guard let name = conversationName(from: candidate) else {
                return nil
            }

            let id = WhatsAppParserSupport.stableId(for: name)
            guard !seenIds.contains(id) else {
                return nil
            }
            seenIds.insert(id)

            let texts = WhatsAppParserSupport.normalizedUniqueTexts(candidate.textFragments)
            let parsedValue = parseConversationValue(candidate.stringValue)
            let combined = candidate.textFragments.joined(separator: " ").lowercased()

            return ConversationSummary(
                id: id,
                accessibilityPath: candidate.accessibilityPath,
                name: name,
                unreadCount: WhatsAppParserSupport.unreadCount(in: texts),
                isPinned: combined.contains("pinned") || combined.contains("fixada"),
                isSelected: combined.contains("selected") || combined.contains("selecionada"),
                lastMessagePreview: parsedValue.preview,
                lastMessageAtText: parsedValue.timeText,
                lastMessageDirection: parsedValue.direction,
                lastMessageStatus: WhatsAppParserSupport.messageStatus(in: combined),
                isTyping: combined.contains("typing") || combined.contains("digitando")
            )
        }

        return conversations.sorted { left, right in
            guard let leftFrame = root.flattened.first(where: { $0.accessibilityPath == left.accessibilityPath })?.frame,
                  let rightFrame = root.flattened.first(where: { $0.accessibilityPath == right.accessibilityPath })?.frame else {
                return left.name < right.name
            }
            return leftFrame.minY < rightFrame.minY
        }
    }

    func conversationCandidates(from accessibilityObject: AccessibilityObject) -> [RawAXNode] {
        guard let chatList = accessibilityMap.chatList(in: accessibilityObject.root) else {
            return []
        }
        return chatList.flattened.filter(isConversationRow(_:))
    }

    private func isConversationRow(_ node: RawAXNode) -> Bool {
        guard node.role == "AXButton" || node.role == "AXStaticText" else {
            return false
        }

        let help = node.help ?? ""
        return help.contains("open chat") && node.frame?.height ?? 0 >= 40
    }

    private func conversationName(from node: RawAXNode) -> String? {
        guard let description = node.nodeDescription else {
            return nil
        }

        let normalized = description
            .normalizedAXText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fragments = normalized
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let first = fragments.first else {
            return nil
        }

        // WhatsApp sometimes splits phone-number chats into comma-separated chunks
        // such as "+ 5 5,5 1,9 6 0 0 0,0 9 3 5". Rebuild those rows so we do not
        // truncate the chat name to only the first fragment.
        if fragments.count > 1, fragments.allSatisfy({ Self.looksLikePhoneFragment($0) }) {
            let rebuilt = fragments
                .map(Self.compactPhoneFragment(_:))
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rebuilt.isEmpty ? first : rebuilt
        }

        return first
    }

    private static func compactPhoneFragment(_ fragment: String) -> String {
        fragment
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    private static func looksLikePhoneFragment(_ fragment: String) -> Bool {
        let compact = compactPhoneFragment(fragment)
        return compact.range(of: #"^[+\d]+$"#, options: .regularExpression) != nil
    }

    private func parseConversationValue(_ value: String?) -> (preview: String?, timeText: String?, direction: MessageDirection) {
        let tokens = WhatsAppParserSupport.axTokens(value)
        guard !tokens.isEmpty else {
            return (nil, nil, .unknown)
        }

        let timeIndex = tokens.firstIndex(where: WhatsAppParserSupport.looksLikeDateOrTime)
        let timeText = timeIndex.map { tokens[$0] }
        let direction = WhatsAppParserSupport.messageDirection(in: tokens.joined(separator: " ").lowercased())
        let previewStart = tokens.first?.lowercased().contains("your message") == true
            || tokens.first?.lowercased().contains("message from") == true
            || tokens.first?.lowercased() == "message"
            || tokens.first?.lowercased().contains("your voice message") == true
            ? 1
            : 0

        let previewEnd = timeIndex ?? tokens.count
        let previewTokens = previewStart < previewEnd ? Array(tokens[previewStart..<previewEnd]) : []
        let preview = previewTokens.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)

        return (preview.isEmpty ? nil : preview, timeText, direction)
    }
}
