import CoreGraphics
import Foundation

struct WhatsAppScreenState: Equatable {
    let conversations: [ConversationSummary]
    let selectedChatName: String?
    let messages: [Message]
    let composeFocused: Bool
    let canSendText: Bool
}

struct WhatsAppScreenParser {
    private let accessibilityMap = WhatsAppAccessibilityMap()

    func parse(snapshot: WhatsAppSnapshot, messageLimit: Int = 10) -> WhatsAppScreenState {
        let root = snapshot.rootNode
        let conversations = parseConversations(from: root)
        let selectedChatName = conversations.first(where: \.isSelected)?.name

        return WhatsAppScreenState(
            conversations: conversations,
            selectedChatName: selectedChatName,
            messages: parseMessages(from: root, selectedChatName: selectedChatName, limit: messageLimit),
            composeFocused: accessibilityMap.composeField(in: root) != nil,
            canSendText: containsText(root, matching: ["send", "enviar"])
        )
    }

    func debugReport(snapshot: WhatsAppSnapshot) -> String {
        let root = snapshot.rootNode
        let flattened = root.flattened
        let nodesWithFrame = flattened.filter { $0.frame != nil }
        let nodesWithText = flattened.filter { !normalizedUniqueTexts($0.textFragments).isEmpty }
        let chatList = accessibilityMap.chatList(in: root)
        let messageList = accessibilityMap.messageList(in: root)

        let conversationCandidates = chatList?.children.filter(isConversationRow(_:)) ?? []

        let parsed = parse(snapshot: snapshot)
        let candidateLines = conversationCandidates.prefix(80).map { node in
            let frame = node.frame.map { "x:\(Int($0.minX)) y:\(Int($0.minY)) w:\(Int($0.width)) h:\(Int($0.height))" } ?? "no-frame"
            let path = node.accessibilityPath.map(String.init).joined(separator: ".")
            let texts = normalizedUniqueTexts(node.textFragments).prefix(8).joined(separator: " | ")
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

    private func parseConversations(from root: RawAXNode) -> [ConversationSummary] {
        let candidates = accessibilityMap.chatList(in: root)?.children.filter(isConversationRow(_:)) ?? []

        var seenIds = Set<String>()
        let conversations = candidates.compactMap { candidate -> ConversationSummary? in
            guard let name = conversationName(from: candidate) else {
                return nil
            }

            let id = stableId(for: name)
            guard !seenIds.contains(id) else {
                return nil
            }
            seenIds.insert(id)

            let texts = normalizedUniqueTexts(candidate.textFragments)
            let parsedValue = parseConversationValue(candidate.stringValue)
            let combined = candidate.textFragments.joined(separator: " ").lowercased()

            return ConversationSummary(
                id: id,
                accessibilityPath: candidate.accessibilityPath,
                name: name,
                unreadCount: unreadCount(in: texts),
                isPinned: combined.contains("pinned") || combined.contains("fixada"),
                isSelected: combined.contains("selected") || combined.contains("selecionada"),
                lastMessagePreview: parsedValue.preview,
                lastMessageAtText: parsedValue.timeText,
                lastMessageDirection: parsedValue.direction,
                lastMessageStatus: messageStatus(in: combined),
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

            let chatId = selectedChatName.map(stableId(for:)) ?? "selected-chat"
            let rawAccessibilityText = normalizedUniqueTexts(node.textFragments).joined(separator: " | ")

            return Message(
                id: stableId(for: signature),
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

    private func isConversationRow(_ node: RawAXNode) -> Bool {
        guard node.role == "AXButton" || node.role == "AXStaticText" else {
            return false
        }

        let help = node.help ?? ""
        return help.contains("open chat") && node.frame?.height ?? 0 >= 40
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

    private func conversationName(from node: RawAXNode) -> String? {
        guard let description = node.nodeDescription else {
            return nil
        }

        return description
            .split(separator: ",")
            .first
            .map(String.init)?
            .normalizedAXText
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedUniqueTexts(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !seen.contains(text) else {
                return nil
            }
            seen.insert(text)
            return text
        }
    }

    private func firstNameCandidate(in texts: [String]) -> String? {
        texts.first { text in
            !looksLikeDateOrTime(text)
                && !looksLikeStatus(text)
                && !looksLikeUnreadText(text)
                && text.count >= 2
                && text.count <= 80
        }
    }

    private func firstPreviewCandidate(in texts: [String], name: String, dateText: String?) -> String? {
        texts.first { text in
            text != name
                && text != dateText
                && !looksLikeDateOrTime(text)
                && !looksLikeStatus(text)
                && !looksLikeUnreadText(text)
        }
    }

    private func parseConversationValue(_ value: String?) -> (preview: String?, timeText: String?, direction: MessageDirection) {
        let tokens = axTokens(value)
        guard !tokens.isEmpty else {
            return (nil, nil, .unknown)
        }

        let timeIndex = tokens.firstIndex(where: looksLikeDateOrTime)
        let timeText = timeIndex.map { tokens[$0] }
        let direction = messageDirection(in: tokens.joined(separator: " ").lowercased())
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

    private func parseMessageDescription(_ description: String?) -> (text: String?, direction: MessageDirection, kind: MessageKind, status: MessageStatus) {
        let tokens = axTokens(description)
        guard let first = tokens.first else {
            return (nil, .unknown, .unknown, .unknown)
        }

        let combined = tokens.joined(separator: " ").lowercased()
        let direction = messageDirection(in: combined)
        let kind = messageKind(in: combined)
        let status = messageStatus(in: combined)
        let metadataIndex = tokens.firstIndex(where: isMessageMetadata(_:)) ?? tokens.count

        if first.lowercased().contains("voice message") {
            return ("Voice message", direction, .voice, status)
        }

        let messageStart = first.lowercased().contains("your message") || first.lowercased() == "message" ? 1 : 0
        let messageTokens = messageStart < metadataIndex ? Array(tokens[messageStart..<metadataIndex]) : []
        let messageText = messageTokens.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)

        return (messageText.isEmpty ? first : messageText, direction, kind, status)
    }

    private func axTokens(_ value: String?) -> [String] {
        guard let value else {
            return []
        }

        return value
            .normalizedAXText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func messageText(from texts: [String]) -> String? {
        texts.first { text in
            !looksLikeDateOrTime(text)
                && !looksLikeStatus(text)
                && !looksLikeUnreadText(text)
                && text.count >= 1
        }
    }

    private func unreadCount(in texts: [String]) -> Int {
        for text in texts {
            let lowercased = text.lowercased()
            if lowercased.contains("unread") || lowercased.contains("não lida") || lowercased.contains("nao lida") {
                let digits = text.filter(\.isNumber)
                if let count = Int(digits), count > 0 {
                    return count
                }
            }

            if let count = Int(text), count > 0, count < 1000 {
                return count
            }
        }

        return 0
    }

    private func messageDirection(in text: String) -> MessageDirection {
        if text.contains("you:") || text.contains("você:") || text.contains("voce:") || text.contains("your message") || text.contains("sent to") {
            return .outgoing
        }
        if text.contains("message from") || text.contains("received from") || text.contains("received in") {
            return .incoming
        }
        return .unknown
    }

    private func messageKind(in text: String) -> MessageKind {
        if text.contains("voice") || text.contains("áudio") || text.contains("audio") {
            return .voice
        }
        if text.contains("image") || text.contains("foto") || text.contains("imagem") {
            return .image
        }
        if text.contains("document") || text.contains("documento") {
            return .document
        }
        if text.contains("deleted") || text.contains("apagada") || text.contains("apagou") {
            return .deleted
        }
        return .text
    }

    private func messageStatus(in text: String) -> MessageStatus {
        if text.contains("read") || text.contains("lida") || text.contains("visualizada") || text == "red" {
            return .read
        }
        if text.contains("delivered") || text.contains("entregue") {
            return .delivered
        }
        if text.contains("sent") || text.contains("enviada") {
            return .sent
        }
        return .unknown
    }

    private func containsText(_ node: RawAXNode, matching needles: [String]) -> Bool {
        let haystack = node.textFragments.joined(separator: " ").lowercased()
        return needles.contains { haystack.contains($0) }
    }

    private func looksLikeChrome(_ texts: [String]) -> Bool {
        let joined = texts.joined(separator: " ").lowercased()
        return joined.contains("search")
            || joined.contains("pesquisar")
            || joined.contains("new chat")
            || joined.contains("nova conversa")
            || joined.contains("settings")
            || joined.contains("configurações")
    }

    private func looksLikeCompose(_ texts: [String]) -> Bool {
        let joined = texts.joined(separator: " ").lowercased()
        return joined.contains("compose message")
            || joined.contains("digite uma mensagem")
            || joined.contains("type a message")
    }

    private func looksLikeDateOrTime(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        if trimmed == "yesterday" || trimmed == "ontem" || trimmed == "today" || trimmed == "hoje" {
            return true
        }
        if trimmed.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil {
            return true
        }
        if compact.range(of: #"^\d{1,2}[a-z]{3,}at\d{1,2}:\d{2}$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^\d{1,2}/\d{1,2}(/\d{2,4})?$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private func isMessageMetadata(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return looksLikeDateOrTime(text)
            || looksLikeStatus(text)
            || lowercased.contains("sent to")
            || lowercased.contains("received from")
            || lowercased.contains("received in")
    }

    private func looksLikeStatus(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("read")
            || lowercased == "red"
            || lowercased.contains("sent")
            || lowercased.contains("delivered")
            || lowercased.contains("lida")
            || lowercased.contains("enviada")
            || lowercased.contains("entregue")
            || lowercased.contains("selected")
            || lowercased.contains("selecionada")
    }

    private func looksLikeUnreadText(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("unread")
            || lowercased.contains("não lida")
            || lowercased.contains("nao lida")
            || (Int(text) ?? 0) > 0
    }

    private func stableId(for value: String) -> String {
        let scalars = value.unicodeScalars.map(\.value)
        let hash = scalars.reduce(UInt64(14_695_981_039_346_656_037)) { partial, scalar in
            (partial ^ UInt64(scalar)).multipliedReportingOverflow(by: 1_099_511_628_211).partialValue
        }
        return String(hash, radix: 16)
    }
}

private extension String {
    var normalizedAXText: String {
        replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: "\u{200F}", with: "")
            .replacingOccurrences(of: "\u{202A}", with: "")
            .replacingOccurrences(of: "\u{202C}", with: "")
    }
}
