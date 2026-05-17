import Foundation

enum MemoriesRepositoryError: LocalizedError {
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

actor MemoriesRepository {
    static let shared = MemoriesRepository()

    struct SaveResult: Equatable {
        let entry: MemoryEntry
        let created: Bool
        let updated: Bool
    }

    private let defaults: UserDefaults
    private let storageKey = "memories.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func list() -> [MemoryEntry] {
        loadAll()
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func get(key: String?) throws -> MemoryEntry {
        let trimmedKey = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            throw MemoriesRepositoryError.missingParameter("key")
        }

        guard let found = loadAll().first(where: { $0.key == trimmedKey }) else {
            throw MemoriesRepositoryError.invalidParameter("Memory not found")
        }

        return found
    }

    func search(query: String?, limit: Int = 3) -> [MemorySearchResult] {
        let trimmedQuery = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let all = loadAll()

        if trimmedQuery.isEmpty {
            return all
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(max(1, limit))
                .map { MemorySearchResult(entry: $0, score: 1) }
        }

        let ranked = all
            .map { entry -> MemorySearchResult in
                let score = TextSimilarity.bestScore(
                    query: trimmedQuery,
                    candidates: [entry.key, entry.content]
                )
                return MemorySearchResult(entry: entry, score: score)
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.entry.updatedAt > $1.entry.updatedAt
                }
                return $0.score > $1.score
            }

        return Array(ranked.prefix(max(1, limit)))
    }

    func save(key: String?, content: String?) throws -> SaveResult {
        let trimmedKey = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            throw MemoriesRepositoryError.missingParameter("key")
        }

        let trimmedContent = (content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.isEmpty {
            throw MemoriesRepositoryError.missingParameter("content")
        }

        var all = loadAll()
        let now = Date()

        let matchingIndexes = all.indices.filter { all[$0].key == trimmedKey }
        if let firstIndex = matchingIndexes.first {
            let existing = all[firstIndex]
            let updatedEntry = MemoryEntry(
                id: existing.id,
                key: trimmedKey,
                content: trimmedContent,
                createdAt: existing.createdAt,
                updatedAt: now
            )
            all[firstIndex] = updatedEntry

            for duplicateIndex in matchingIndexes.dropFirst().sorted(by: >) {
                all.remove(at: duplicateIndex)
            }

            persistAll(all)
            return SaveResult(entry: updatedEntry, created: false, updated: true)
        }

        let entry = MemoryEntry(
            id: UUID(),
            key: trimmedKey,
            content: trimmedContent,
            createdAt: now,
            updatedAt: now
        )
        all.append(entry)
        persistAll(all)
        return SaveResult(entry: entry, created: true, updated: false)
    }

    func delete(id: UUID?) throws -> Bool {
        guard let id else {
            throw MemoriesRepositoryError.missingParameter("id")
        }

        var all = loadAll()
        let originalCount = all.count
        all.removeAll { $0.id == id }
        guard all.count != originalCount else {
            return false
        }
        persistAll(all)
        return true
    }

    func delete(key: String?) throws -> Bool {
        let trimmedKey = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            throw MemoriesRepositoryError.missingParameter("key")
        }

        var all = loadAll()
        let originalCount = all.count
        all.removeAll { $0.key == trimmedKey }
        guard all.count != originalCount else {
            return false
        }
        persistAll(all)
        return true
    }

    private func loadAll() -> [MemoryEntry] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([MemoryEntry].self, from: data)) ?? []
    }

    private func persistAll(_ entries: [MemoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: .memoriesRepositoryDidChange, object: nil)
    }
}
