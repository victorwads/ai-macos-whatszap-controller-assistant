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

    func list(query: String? = nil) -> [NicknameEntry] {
        let all = loadAll()

        let trimmedQuery = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return all.sorted { $0.createdAt > $1.createdAt }
        }

        let normalizedQuery = normalizedNicknameSearchText(trimmedQuery)

        let exactMatches = all.filter {
            normalizedNicknameSearchText($0.nickname) == normalizedQuery
                || normalizedNicknameSearchText($0.originalName) == normalizedQuery
                || normalizedNicknameSearchText($0.chatId ?? "") == normalizedQuery
        }
        if !exactMatches.isEmpty {
            let exactOriginalNames = Set(exactMatches.map { normalizedNicknameSearchText($0.originalName) })
            let exactChatIds = Set(exactMatches.compactMap { $0.chatId }.map(normalizedNicknameSearchText))
            return all
                .filter {
                    exactOriginalNames.contains(normalizedNicknameSearchText($0.originalName))
                        || exactChatIds.contains(normalizedNicknameSearchText($0.chatId ?? ""))
                }
                .sorted { $0.createdAt > $1.createdAt }
        }

        let matchingOriginalNames = Set(
            all
                .filter {
                    normalizedNicknameSearchText($0.nickname).contains(normalizedQuery)
                        || normalizedNicknameSearchText($0.originalName).contains(normalizedQuery)
                        || normalizedNicknameSearchText($0.chatId ?? "").contains(normalizedQuery)
                }
                .map { normalizedNicknameSearchText($0.originalName) }
        )
        guard !matchingOriginalNames.isEmpty else {
            return []
        }

        return all
            .filter { matchingOriginalNames.contains(normalizedNicknameSearchText($0.originalName)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func save(originalName: String?, chatId: String?, nickname: String?) throws -> SaveResult {
        let trimmedOriginalName = (originalName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOriginalName.isEmpty {
            throw NicknamesRepositoryError.missingParameter("originalName")
        }

        let trimmedNickname = (nickname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNickname.isEmpty {
            throw NicknamesRepositoryError.missingParameter("nickname")
        }

        let trimmedChatId = normalizedOptionalString(chatId)

        var entries = loadAll()
        if let index = entries.firstIndex(where: {
            normalizedNicknameSearchText($0.originalName) == normalizedNicknameSearchText(trimmedOriginalName)
                && normalizedNicknameSearchText($0.nickname) == normalizedNicknameSearchText(trimmedNickname)
                && normalizedOptionalString($0.chatId) == trimmedChatId
        }) {
            return SaveResult(entry: entries[index], created: false)
        }

        if let index = entries.firstIndex(where: {
            normalizedNicknameSearchText($0.originalName) == normalizedNicknameSearchText(trimmedOriginalName)
                && normalizedNicknameSearchText($0.nickname) == normalizedNicknameSearchText(trimmedNickname)
        }) {
            if entries[index].chatId == nil, let trimmedChatId {
                entries[index] = NicknameEntry(
                    id: entries[index].id,
                    originalName: entries[index].originalName,
                    nickname: entries[index].nickname,
                    chatId: trimmedChatId,
                    createdAt: entries[index].createdAt
                )
                persistAll(entries)
                return SaveResult(entry: entries[index], created: false)
            }
            return SaveResult(entry: entries[index], created: false)
        }

        let entry = NicknameEntry(
            id: UUID(),
            originalName: trimmedOriginalName,
            nickname: trimmedNickname,
            chatId: trimmedChatId,
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
        NotificationCenter.default.post(name: .nicknamesRepositoryDidChange, object: nil)
    }

    private func normalizedNicknameSearchText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
