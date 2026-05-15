import Combine
import Foundation

extension AppModel {
    func openConversation(_ conversation: ConversationSummary) {
        memoryStore.selectConversation(id: conversation.id)
    }

    func clearConversationHistoryCache() {
        memoryStore.clearAllCachedChatHistories()
    }

    func bindMemoryStore() {
        memoryStore.$conversations
            .sink { [weak self] in
                self?.conversations = $0
            }
            .store(in: &cancellables)

        memoryStore.$selectedChatState
            .sink { [weak self] in
                self?.selectedChatState = $0
            }
            .store(in: &cancellables)

        memoryStore.$selectedConversationId
            .sink { [weak self] in
                self?.selectedConversationId = $0
            }
            .store(in: &cancellables)
    }

    func filteredConversations(_ conversations: [ConversationSummary]) -> [ConversationSummary] {
        switch conversationAccessMode {
        case .allowAllExceptDeny:
            return conversations.filter { !denyConversationNames.contains($0.name) }
        case .denyAllExceptAllow:
            // Keep all conversations visible so the user can allow them explicitly.
            return conversations
        }
    }
}
