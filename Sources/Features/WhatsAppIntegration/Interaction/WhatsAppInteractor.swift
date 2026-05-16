import Foundation

@MainActor
struct WhatsAppInteractor {
    private let selectionHandler = WhatsAppConversationSelectionHandler()
    private let messageSendHandler = WhatsAppMessageSendHandler()

    @MainActor
    func selectConversation(_ conversation: ConversationSummary, using accessibility: AccessibilityService) throws {
        try selectionHandler.selectConversation(conversation, using: accessibility)
    }

    @MainActor
    func sendMessage(_ text: String, using accessibility: AccessibilityService) throws {
        try messageSendHandler.sendMessage(text, using: accessibility)
    }
}
