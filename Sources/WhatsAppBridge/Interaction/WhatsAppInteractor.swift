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
