import Foundation

@MainActor
protocol WhatsAppConversationInteractor {
    func openConversation(_ conversation: ConversationSummary) async throws
}

@MainActor
protocol WhatsAppConversationParser {
    func listConversations() async throws -> [ConversationSummary]
    func readMessages(limit: Int) async throws -> (selectedChatName: String?, messages: [Message], composeFocused: Bool, canSendText: Bool)
}

@MainActor
protocol WhatsAppIntegrationProvider {
    var kind: WhatsAppIntegrationMode { get }
    var parser: WhatsAppConversationParser { get }
    var interactor: WhatsAppConversationInteractor { get }
}
