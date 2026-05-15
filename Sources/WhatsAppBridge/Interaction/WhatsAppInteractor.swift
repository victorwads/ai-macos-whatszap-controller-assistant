import Foundation

struct WhatsAppInteractor {
    private let accessibilityMap = WhatsAppAccessibilityMap()

    func selectConversation(_ conversation: ConversationSummary, using accessibility: AccessibilityService) throws {
        do {
            try accessibility.pressNode(at: conversation.accessibilityPath)
        } catch {
            try openConversationBySearch(conversation.name, using: accessibility)
        }
    }

    func sendMessage(_ text: String, in snapshot: WhatsAppSnapshot, using accessibility: AccessibilityService) throws {
        guard let composePath = accessibilityMap.composeField(in: snapshot.rootNode)?.accessibilityPath else {
            throw AccessibilityError.nodeNotFound
        }

        try accessibility.sendText(text, to: composePath)
        try triggerSend(in: snapshot, using: accessibility, composePath: composePath)
    }

    /// Attempts to send the currently composed message.
    /// Keeps the "send" action separate so callers can retry Enter without retyping.
    func triggerSend(in snapshot: WhatsAppSnapshot, using accessibility: AccessibilityService) throws {
        guard let composePath = accessibilityMap.composeField(in: snapshot.rootNode)?.accessibilityPath else {
            throw AccessibilityError.nodeNotFound
        }
        try triggerSend(in: snapshot, using: accessibility, composePath: composePath)
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
        do {
            try accessibility.pressEnterKey()
        } catch {
            // Fallback if key injection fails: press the Send button via AX.
            if let sendPath = accessibilityMap.sendButton(in: snapshot.rootNode)?.accessibilityPath {
                try accessibility.pressNode(at: sendPath)
            } else {
                throw error
            }
        }
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
