import Foundation

extension AppModel {
    func loadChatListSignatures() {
        do {
            if let payload = try ChatListSignaturesRepository.shared.load() {
                listSignaturesById = payload.signaturesByChatId
                appendLog("Loaded \(listSignaturesById.count) persisted chat signatures.")
            } else {
                listSignaturesById = [:]
            }
        } catch {
            listSignaturesById = [:]
            appendLog("Failed to decode persisted chat signatures; clearing cache. (\(error.localizedDescription))", level: .warning)
        }
    }

    func persistChatListSignatures() {
        let payload = PersistedChatListSignatures(
            version: 1,
            updatedAt: Date(),
            signaturesByChatId: listSignaturesById
        )

        do {
            try ChatListSignaturesRepository.shared.save(payload)
        } catch {
            appendLog("Failed to persist chat signatures: \(error.localizedDescription)", level: .warning)
        }
    }
}
