import Foundation

@MainActor
final class ChatListSignaturesRepository {
    static let shared = ChatListSignaturesRepository()

    private let defaults: UserDefaults
    private let storageKey = "chatListSignatures.v1"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws -> PersistedChatListSignatures? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }
        return try JSONDecoder().decode(PersistedChatListSignatures.self, from: data)
    }

    func save(_ payload: PersistedChatListSignatures) throws {
        let data = try JSONEncoder().encode(payload)
        defaults.set(data, forKey: storageKey)
    }
}
