import Foundation

enum WhatsAppParserSupport {
    static func normalizedUniqueTexts(_ values: [String]) -> [String] {
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

    static func axTokens(_ value: String?) -> [String] {
        guard let value else {
            return []
        }

        return value
            .normalizedAXText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func unreadCount(in texts: [String]) -> Int {
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

    static func messageDirection(in text: String) -> MessageDirection {
        if text.contains("you:") || text.contains("você:") || text.contains("voce:") || text.contains("your message") || text.contains("sent to") {
            return .outgoing
        }
        if text.contains("message from") || text.contains("received from") || text.contains("received in") {
            return .incoming
        }
        return .unknown
    }

    static func messageKind(in text: String) -> MessageKind {
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

    static func messageStatus(in text: String) -> MessageStatus {
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

    static func normalizedMessageTimestampText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func messageTimestampText(in tokens: [String]) -> String? {
        tokens.first(where: looksLikeDateOrTime(_:))
    }

    static func messageDeduplicationKey(
        chatId: String,
        direction: MessageDirection,
        kind: MessageKind,
        text: String,
        timestampText: String?
    ) -> String {
        let normalizedText = text
            .normalizedAXText
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let normalizedTimestamp = normalizedMessageTimestampText(timestampText)?.lowercased() ?? ""

        return [
            chatId,
            direction.rawValue,
            kind.rawValue,
            normalizedText,
            normalizedTimestamp
        ].joined(separator: "|")
    }

    static func looksLikeDateOrTime(_ text: String) -> Bool {
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

    static func looksLikeStatus(_ text: String) -> Bool {
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

    static func isMessageMetadata(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return looksLikeDateOrTime(text)
            || looksLikeStatus(text)
            || lowercased.contains("sent to")
            || lowercased.contains("received from")
            || lowercased.contains("received in")
    }

    static func stableId(for value: String) -> String {
        let scalars = value.unicodeScalars.map(\.value)
        let hash = scalars.reduce(UInt64(14_695_981_039_346_656_037)) { partial, scalar in
            (partial ^ UInt64(scalar)).multipliedReportingOverflow(by: 1_099_511_628_211).partialValue
        }
        return String(hash, radix: 16)
    }

    static func chatNameComparisonKey(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        let normalized = value
            .normalizedAXText
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        return normalized
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

extension String {
    var normalizedAXText: String {
        replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: "\u{200F}", with: "")
            .replacingOccurrences(of: "\u{202A}", with: "")
            .replacingOccurrences(of: "\u{202C}", with: "")
    }
}
