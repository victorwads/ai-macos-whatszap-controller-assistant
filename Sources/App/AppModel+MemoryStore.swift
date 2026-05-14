import Combine
import Foundation

extension AppModel {
    func openConversation(_ conversation: ConversationSummary) {
        memoryStore.selectConversation(id: conversation.id)
    }

    func isBlocked(_ conversationName: String) -> Bool {
        blockedConversationNames.contains(conversationName)
    }

    func toggleBlockedConversation(_ conversationName: String) {
        if isBlocked(conversationName) {
            unblockConversation(named: conversationName)
        } else {
            blockConversation(named: conversationName)
        }
    }

    func unblockConversation(named conversationName: String) {
        blockedConversationNames.removeAll { $0 == conversationName }
        persistBlockedConversationNames()
        appendLog("Removed \(conversationName) from blacklist.")
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
        conversations.filter { !isBlocked($0.name) }
    }

    func loadBlockedConversationNames() {
        blockedConversationNames = UserDefaults.standard.stringArray(forKey: blockedConversationDefaultsKey) ?? []
        blockedConversationNames.sort()
    }

    func persistBlockedConversationNames() {
        UserDefaults.standard.set(blockedConversationNames, forKey: blockedConversationDefaultsKey)
    }

    private func blockConversation(named conversationName: String) {
        guard !isBlocked(conversationName) else {
            return
        }

        blockedConversationNames.append(conversationName)
        blockedConversationNames.sort()
        persistBlockedConversationNames()

        let blockedIDs = conversations
            .filter { $0.name == conversationName }
            .map(\.id)

        for blockedID in blockedIDs {
            listSignaturesById.removeValue(forKey: blockedID)
            memoryStore.removeConversation(id: blockedID)
        }
        persistChatListSignatures()

        appendLog("Added \(conversationName) to blacklist.")
    }
}
