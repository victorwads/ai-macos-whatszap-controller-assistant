import Foundation

struct WhatsAppInteractor {
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
        // Some WhatsApp AX values appear truncated in-place. Accept a conservative match:
        // if the current value is a prefix of the target (or vice-versa), and the overlap is meaningful.
        if current.count >= 12, target.hasPrefix(current) { return true }
        if target.count >= 12, current.hasPrefix(target) { return true }
        // If current contains a meaningful suffix of the target, it's likely the full text is present
        // but AX is dropping some earlier content.
        let suffixLen = min(18, target.count)
        if suffixLen >= 12 {
            let suffix = String(target.suffix(suffixLen))
            if current.contains(suffix) { return true }
        }
        return false
    }

    func selectConversation(_ conversation: ConversationSummary, using accessibility: AccessibilityService) throws {
        do {
            try accessibility.pressNode(at: conversation.accessibilityPath)
        } catch {
            try openConversationBySearch(conversation.name, using: accessibility)
        }
    }

    func sendMessage(_ text: String, in snapshot: WhatsAppSnapshot, using accessibility: AccessibilityService) throws {
        // Re-resolve composePath from a fresh snapshot because AX child indexes can shift between
        // snapshot capture and the moment we type (causing stale accessibilityPath lookups).
        let liveSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
        guard let composePath = accessibilityMap.composeField(in: liveSnapshot.rootNode)?.accessibilityPath else {
            throw AccessibilityError.nodeNotFound
        }

        // Stage 1: type message and verify the compose field contains exactly what we intended.
        // WhatsApp can occasionally miss part of the injected text if focus is stolen mid-flight.
        let normalizedTarget = normalizeComposeTextForComparison(text)
        var typedOK = false
        for attempt in 1...3 {
            try accessibility.sendText(text, to: composePath)

            // Wait for the AX value to catch up, without relying on one fixed sleep.
            var lastSeen: String?
            for _ in 0..<100 { // ~2s max (100 * 0.02s)
                let current = (try? accessibility.readValue(at: composePath)).map(normalizeComposeTextForComparison(_:)) ?? ""
                if composeLooksLikeTarget(current, target: normalizedTarget) {
                    typedOK = true
                    break
                }
                // If text is still changing, keep waiting.
                if current != lastSeen {
                    lastSeen = current
                }
                Thread.sleep(forTimeInterval: 0.02)
            }

            if typedOK { break }

            // If we couldn't confirm, retype. This is safer than sending a potentially truncated message.
            if attempt < 3 {
                continue
            }
        }

        if !typedOK {
            throw AccessibilityError.actionFailed(-3)
        }

        try triggerSend(in: liveSnapshot, using: accessibility, composePath: composePath)
    }

    /// Attempts to send the currently composed message.
    /// Keeps the "send" action separate so callers can retry Enter without retyping.
    func triggerSend(in snapshot: WhatsAppSnapshot, using accessibility: AccessibilityService) throws {
        let liveSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
        guard let composePath = accessibilityMap.composeField(in: liveSnapshot.rootNode)?.accessibilityPath else {
            throw AccessibilityError.nodeNotFound
        }
        try triggerSend(in: liveSnapshot, using: accessibility, composePath: composePath)
    }

    private func triggerSend(in snapshot: WhatsAppSnapshot, using accessibility: AccessibilityService, composePath: [Int]) throws {
        // Re-activate WhatsApp right before Enter. Without this, the user can steal focus mid-flight
        // and the Enter key event goes to the wrong app.
        try accessibility.ensureWhatsAppActive()
        // WhatsApp can require an actual "press" interaction (not only AXFocused=true) for Enter-to-send.
        // Use AXPress only (no coordinate click) to avoid hitting message rows.
        try? accessibility.pressNodeAXOnly(at: composePath)
        try? accessibility.focusNode(at: composePath)
        Thread.sleep(forTimeInterval: 0.05)
        // We intentionally avoid clicking the Send button. Clicking is brittle (emoji button lives
        // near the compose area and coordinate clicks can hit the wrong target). Prefer Enter only.
        try accessibility.pressEnterKey()
    }

    private func openConversationBySearch(_ name: String, using accessibility: AccessibilityService) throws {
        // Capture a shallow snapshot and locate the search field.
        let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 10)
        let root = snapshot.rootNode

        guard let searchField = root.firstDescendant(where: { node in
            if node.subrole == "AXSearchField" { return true }
            return node.nodeDescription?.normalizedAXText.trimmingCharacters(in: .whitespacesAndNewlines) == "Search"
        }) else {
            throw AccessibilityError.nodeNotFound
        }

        try accessibility.sendText(name, to: searchField.accessibilityPath)
        try accessibility.pressEnterKey()
    }
}
