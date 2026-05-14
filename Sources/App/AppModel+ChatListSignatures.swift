import Foundation

extension AppModel {
    func loadChatListSignatures() {
        guard let data = UserDefaults.standard.data(forKey: chatListSignaturesDefaultsKey) else {
            listSignaturesById = [:]
            return
        }

        do {
            let payload = try JSONDecoder().decode(PersistedChatListSignatures.self, from: data)
            listSignaturesById = payload.signaturesByChatId
            appendLog("Loaded \(listSignaturesById.count) persisted chat signatures.")
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
            let data = try JSONEncoder().encode(payload)
            UserDefaults.standard.set(data, forKey: chatListSignaturesDefaultsKey)
        } catch {
            appendLog("Failed to persist chat signatures: \(error.localizedDescription)", level: .warning)
        }
    }
}

