import Foundation

@MainActor
struct WhatsAppMessageSendHandler {
    private let accessibilityMap = WhatsAppAccessibilityMap()

    private func normalizeComposeTextForComparison(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func composeLooksLikeTarget(_ current: String, target: String) -> Bool {
        if current == target { return true }
        if current.count >= 12, target.hasPrefix(current) { return true }
        if target.count >= 12, current.hasPrefix(target) { return true }
        let suffixLen = min(18, target.count)
        if suffixLen >= 12 {
            let suffix = String(target.suffix(suffixLen))
            if current.contains(suffix) { return true }
        }
        return false
    }

    func sendMessage(_ text: String, using accessibility: AccessibilityService) throws {
        let liveSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
        guard let composePath = accessibilityMap.composeField(in: liveSnapshot.rootNode)?.accessibilityPath else {
            throw AccessibilityError.nodeNotFound
        }

        let normalizedTarget = normalizeComposeTextForComparison(text)
        var typedOK = false
        for attempt in 1...3 {
            try accessibility.sendText(text, to: composePath)

            var lastSeen: String?
            for _ in 0..<100 {
                let current = (try? accessibility.readValue(at: composePath)).map(normalizeComposeTextForComparison(_:)) ?? ""
                if composeLooksLikeTarget(current, target: normalizedTarget) {
                    typedOK = true
                    break
                }
                if current != lastSeen {
                    lastSeen = current
                }
                Thread.sleep(forTimeInterval: 0.02)
            }

            if typedOK { break }
            if attempt < 3 {
                continue
            }
        }

        if !typedOK {
            throw AccessibilityError.actionFailed(-3)
        }

        try triggerSend(using: accessibility, composePath: composePath)
    }

    private func triggerSend(using accessibility: AccessibilityService, composePath: [Int]) throws {
        try accessibility.ensureWhatsAppActive()
        try? accessibility.pressNodeAXOnly(at: composePath)
        try accessibility.focusNode(at: composePath)
        Thread.sleep(forTimeInterval: 0.05)
        try accessibility.pressEnterKey()
    }
}
