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
    func parse(snapshot: WhatsAppSnapshot, messageLimit: Int = 10) -> WhatsAppScreenState {
        let root = snapshot.rootNode
        let conversations = parseConversations(from: root)
        let selectedChatName = conversations.first(where: \.isSelected)?.name

        return WhatsAppScreenState(
            conversations: conversations,
            selectedChatName: selectedChatName,
            messages: parseMessages(from: root, selectedChatName: selectedChatName, limit: messageLimit),
            composeFocused: containsText(root, matching: ["compose message", "mensagem", "digite uma mensagem"]),
            canSendText: containsText(root, matching: ["send", "enviar"])
        )
    }

    private func parseConversations(from root: RawAXNode) -> [ConversationSummary] {
        let sidebarLimit = sidebarMaxX(from: root)
        let candidates = root.flattened.filter { node in
            guard let frame = node.frame else {
                return false
            }

            let textFragments = normalizedUniqueTexts(node.textFragments)
            guard textFragments.count >= 2 else {
                return false
            }

            return frame.minX <= sidebarLimit
                && frame.width >= 180
                && frame.width <= 620
                && frame.height >= 36
                && frame.height <= 128
                && !looksLikeChrome(textFragments)
        }

        var seenIds = Set<String>()
        let conversations = candidates.compactMap { candidate -> ConversationSummary? in
            let texts = normalizedUniqueTexts(candidate.textFragments)
            guard let name = firstNameCandidate(in: texts) else {
                return nil
            }

            let id = stableId(for: name)
            guard !seenIds.contains(id) else {
                return nil
            }
            seenIds.insert(id)

            let dateText = texts.first(where: looksLikeDateOrTime)
            let preview = firstPreviewCandidate(in: texts, name: name, dateText: dateText)
            let combined = texts.joined(separator: " ").lowercased()

            return ConversationSummary(
                id: id,
                accessibilityPath: candidate.accessibilityPath,
                name: name,
                unreadCount: unreadCount(in: texts),
                isPinned: combined.contains("pinned") || combined.contains("fixada"),
                isSelected: combined.contains("selected") || combined.contains("selecionada"),
                lastMessagePreview: preview,
                lastMessageAtText: dateText,
                lastMessageDirection: messageDirection(in: combined),
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
        let sidebarLimit = sidebarMaxX(from: root)
        let candidates = root.flattened.filter { node in
            guard let frame = node.frame else {
                return false
            }

            let texts = normalizedUniqueTexts(node.textFragments)
            guard !texts.isEmpty else {
                return false
            }

            return frame.minX > sidebarLimit
                && frame.height >= 18
                && frame.height <= 260
                && !looksLikeChrome(texts)
                && !looksLikeCompose(texts)
        }

        var seen = Set<String>()
        let messages = candidates.compactMap { node -> Message? in
            let texts = normalizedUniqueTexts(node.textFragments)
            guard let rawText = messageText(from: texts) else {
                return nil
            }

            let signature = "\(Int(node.frame?.minY ?? 0))|\(rawText)"
            guard !seen.contains(signature) else {
                return nil
            }
            seen.insert(signature)

            let combined = texts.joined(separator: " ").lowercased()
            let chatId = selectedChatName.map(stableId(for:)) ?? "selected-chat"

            return Message(
                id: stableId(for: signature),
                chatId: chatId,
                direction: messageDirection(in: combined),
                kind: messageKind(in: combined),
                text: rawText,
                durationSeconds: nil,
                timestamp: nil,
                status: messageStatus(in: combined),
                rawAccessibilityText: texts.joined(separator: " | ")
            )
        }

        return Array(messages.suffix(limit))
    }

    private func sidebarMaxX(from root: RawAXNode) -> CGFloat {
        let windowWidth = root.frame?.width ?? 1200
        return min(520, max(320, windowWidth * 0.45))
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
        if text.contains("you:") || text.contains("você:") || text.contains("voce:") {
            return .outgoing
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
        if text.contains("read") || text.contains("lida") || text.contains("visualizada") {
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
        if trimmed == "yesterday" || trimmed == "ontem" || trimmed == "today" || trimmed == "hoje" {
            return true
        }
        if trimmed.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^\d{1,2}/\d{1,2}(/\d{2,4})?$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private func looksLikeStatus(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("read")
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
