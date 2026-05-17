import Foundation

@MainActor
final class DesktopAXProvider: WhatsAppIntegrationProvider {
    let kind: WhatsAppIntegrationMode = .desktopAX

    let parser: WhatsAppConversationParser
    let interactor: WhatsAppConversationInteractor

    init(
        accessibility: AccessibilityService,
        parser: WhatsAppAppParser,
        interactor: WhatsAppInteractor
    ) {
        self.parser = DesktopAXParser(accessibility: accessibility, parser: parser)
        self.interactor = DesktopAXInteractor(accessibility: accessibility, interactor: interactor, parser: parser)
    }
}

@MainActor
private struct DesktopAXParser: WhatsAppConversationParser {
    let accessibility: AccessibilityService
    let parser: WhatsAppAppParser

    func listConversations() async throws -> [ConversationSummary] {
        let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
        let screenState = parser.parse(snapshot: snapshot, messageLimit: 10)
        return screenState.conversations
    }

    func readMessages(limit: Int) async throws -> (selectedChatName: String?, messages: [Message], composeFocused: Bool, canSendText: Bool) {
        let snapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
        let screenState = parser.parse(snapshot: snapshot, messageLimit: limit)
        return (screenState.selectedChatName, screenState.messages, screenState.composeFocused, screenState.canSendText)
    }
}

@MainActor
private struct DesktopAXInteractor: WhatsAppConversationInteractor {
    let accessibility: AccessibilityService
    let interactor: WhatsAppInteractor
    let parser: WhatsAppAppParser

    func openConversation(_ conversation: ConversationSummary) async throws {
        let targetNameKey = WhatsAppParserSupport.chatNameComparisonKey(conversation.name)

        for _ in 1...3 {
            let baselineSnapshot = try accessibility.captureWhatsAppSnapshot(maxDepth: 14)
            let baselineState = parser.parse(snapshot: baselineSnapshot, messageLimit: 1)
            if WhatsAppParserSupport.chatNameComparisonKey(baselineState.selectedChatName) == targetNameKey {
                return
            }

            let liveConversation = baselineState.conversations.first {
                $0.id == conversation.id || WhatsAppParserSupport.chatNameComparisonKey($0.name) == targetNameKey
            } ?? conversation

            try interactor.selectConversation(liveConversation, using: accessibility)
            try await Task.sleep(for: .milliseconds(400))
        }

        throw AccessibilityError.actionFailed(-1)
    }
}

