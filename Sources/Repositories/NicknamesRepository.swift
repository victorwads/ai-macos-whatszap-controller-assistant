import Foundation

enum NicknamesRepositoryError: LocalizedError {
    case missingParameter(String)
    case invalidParameter(String)

    var errorDescription: String? {
        switch self {
        case .missingParameter(let name):
            return "Missing parameter: \(name)"
        case .invalidParameter(let message):
            return message
        }
    }
}

actor NicknamesRepository {
    static let shared = NicknamesRepository()

    struct SaveResult: Codable, Equatable {
        let entry: NicknameEntry
        let created: Bool
    }

    private let defaults: UserDefaults
    private let storageKey = "nicknames.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func list(chatId: String? = nil) -> [NicknameEntry] {
        let all = loadAll()
        if let chatId, !chatId.isEmpty {
            return all
                .filter { $0.chatId == chatId }
                .sorted { $0.createdAt > $1.createdAt }
        }
        return all.sorted { $0.createdAt > $1.createdAt }
    }

    func save(chatId: String?, chatName: String?, nickname: String?) throws -> SaveResult {
        let trimmedChatId = (chatId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedChatId.isEmpty {
            throw NicknamesRepositoryError.missingParameter("chatId")
        }

        let trimmedChatName = (chatName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedChatName.isEmpty {
            throw NicknamesRepositoryError.missingParameter("chatName")
        }

        let trimmedNickname = (nickname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNickname.isEmpty {
            throw NicknamesRepositoryError.missingParameter("nickname")
        }

        var entries = loadAll()
        if let existing = entries.first(where: { $0.chatId == trimmedChatId && $0.nickname == trimmedNickname }) {
            return SaveResult(entry: existing, created: false)
        }

        let entry = NicknameEntry(
            id: UUID(),
            chatId: trimmedChatId,
            chatName: trimmedChatName,
            nickname: trimmedNickname,
            createdAt: Date()
        )
        entries.append(entry)
        persistAll(entries)
        return SaveResult(entry: entry, created: true)
    }

    func delete(id: UUID?) throws -> Bool {
        guard let id else {
            throw NicknamesRepositoryError.missingParameter("id")
        }

        var entries = loadAll()
        let originalCount = entries.count
        entries.removeAll { $0.id == id }
        guard entries.count != originalCount else {
            return false
        }
        persistAll(entries)
        return true
    }

    private func loadAll() -> [NicknameEntry] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([NicknameEntry].self, from: data)) ?? []
    }

    private func persistAll(_ entries: [NicknameEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}

