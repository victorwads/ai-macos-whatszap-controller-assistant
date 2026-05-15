import Combine
import Foundation

extension AppModel {
    func loadConversationAccessSettings() {
        let loaded = ConversationAccessRepository.shared.load()
        conversationAccessMode = loaded.mode
        denyConversationNames = loaded.deny
        allowConversationNames = loaded.allow

        $conversationAccessMode
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                ConversationAccessRepository.shared.save(
                    mode: value,
                    deny: self.denyConversationNames,
                    allow: self.allowConversationNames
                )
            }
            .store(in: &cancellables)

        $denyConversationNames
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                ConversationAccessRepository.shared.save(
                    mode: self.conversationAccessMode,
                    deny: value,
                    allow: self.allowConversationNames
                )
            }
            .store(in: &cancellables)

        $allowConversationNames
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                ConversationAccessRepository.shared.save(
                    mode: self.conversationAccessMode,
                    deny: self.denyConversationNames,
                    allow: value
                )
            }
            .store(in: &cancellables)
    }

    func isBlocked(_ conversationName: String) -> Bool {
        switch conversationAccessMode {
        case .allowAllExceptDeny:
            return denyConversationNames.contains(conversationName)
        case .denyAllExceptAllow:
            return !allowConversationNames.contains(conversationName)
        }
    }

    func toggleConversationAccess(_ conversationName: String) {
        switch conversationAccessMode {
        case .allowAllExceptDeny:
            if denyConversationNames.contains(conversationName) {
                removeFromDenyList(conversationName)
            } else {
                addToDenyList(conversationName)
            }
        case .denyAllExceptAllow:
            if allowConversationNames.contains(conversationName) {
                removeFromAllowList(conversationName)
            } else {
                addToAllowList(conversationName)
            }
        }
    }

    func removeFromDenyList(_ conversationName: String) {
        denyConversationNames.removeAll { $0 == conversationName }
        appendLog("Removed \(conversationName) from deny list.")
    }

    func removeFromAllowList(_ conversationName: String) {
        allowConversationNames.removeAll { $0 == conversationName }
        appendLog("Removed \(conversationName) from allow list.")
    }

    private func addToDenyList(_ conversationName: String) {
        guard !denyConversationNames.contains(conversationName) else { return }
        denyConversationNames.append(conversationName)
        denyConversationNames.sort()

        let deniedIDs = conversations
            .filter { $0.name == conversationName }
            .map(\.id)

        for deniedID in deniedIDs {
            listSignaturesById.removeValue(forKey: deniedID)
            memoryStore.removeConversation(id: deniedID)
        }
        persistChatListSignatures()

        appendLog("Added \(conversationName) to deny list.")
    }

    private func addToAllowList(_ conversationName: String) {
        guard !allowConversationNames.contains(conversationName) else { return }
        allowConversationNames.append(conversationName)
        allowConversationNames.sort()
        appendLog("Added \(conversationName) to allow list.")
    }
}
