import Foundation

struct WhatsAppInteractor {
    private let accessibilityMap = WhatsAppAccessibilityMap()

    func selectConversation(_ conversation: ConversationSummary, using accessibility: AccessibilityService) throws {
        try accessibility.pressNode(at: conversation.accessibilityPath)
    }

    func sendMessage(_ text: String, in snapshot: WhatsAppSnapshot, using accessibility: AccessibilityService) throws {
        guard let composePath = accessibilityMap.composeField(in: snapshot.rootNode)?.accessibilityPath else {
            throw AccessibilityError.nodeNotFound
        }
        guard let sendButtonPath = accessibilityMap.sendButton(in: snapshot.rootNode)?.accessibilityPath else {
            throw AccessibilityError.nodeNotFound
        }

        try accessibility.setValue(text, at: composePath)
        try accessibility.pressNode(at: sendButtonPath)
    }
}
