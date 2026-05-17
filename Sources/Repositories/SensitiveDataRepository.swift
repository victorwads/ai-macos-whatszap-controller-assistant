import Foundation

enum SensitiveDataRepositoryError: LocalizedError {
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

actor SensitiveDataRepository {
    static let shared = SensitiveDataRepository()

    struct SaveResult: Equatable {
        let entry: SensitiveDataEntry
        let created: Bool
        let updated: Bool
    }

    private struct Store: Codable {
        var entries: [SensitiveDataEntry]
        var audits: [SensitiveDataAuditEntry]
    }

    private let store: KeychainDataStore

    init(store: KeychainDataStore = KeychainDataStore(service: "dev.wads.AssistantMCPServer", account: "sensitive-data")) {
        self.store = store
    }

    func peekEntries() -> [SensitiveDataEntry] {
        loadStore().entries.sorted { $0.updatedAt > $1.updatedAt }
    }

    func list(subjectId: String?, reason: String?) throws -> [SensitiveDataEntry] {
        let trimmedSubjectId = try required(subjectId, parameter: "subjectId")
        let trimmedReason = try required(reason, parameter: "reason")
        var store = loadStore()
        store.audits.insert(
            SensitiveDataAuditEntry(
                action: .list,
                subjectId: trimmedSubjectId,
                reason: trimmedReason,
                matchedCount: store.entries.count
            ),
            at: 0
        )
        try persist(store)
        return store.entries.sorted { $0.updatedAt > $1.updatedAt }
    }

    func listAudits(limit: Int = 50) -> [SensitiveDataAuditEntry] {
        let all = loadStore().audits
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                return lhs.timestamp > rhs.timestamp
            }
        return Array(all.prefix(max(1, limit)))
    }

    func previewSearch(query: String?, limit: Int = 3) -> [SensitiveDataSearchResult] {
        searchResults(query: query, limit: limit)
    }

    func search(query: String?, limit: Int = 3, subjectId: String?, reason: String?) throws -> [SensitiveDataSearchResult] {
        let trimmedQuery = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubjectId = try required(subjectId, parameter: "subjectId")
        let trimmedReason = try required(reason, parameter: "reason")
        let ranked = searchResults(query: trimmedQuery, limit: limit)

        let limited = Array(ranked.prefix(max(1, limit)))
        try recordAudit(
            action: .search,
            subjectId: trimmedSubjectId,
            reason: trimmedReason,
            query: trimmedQuery.isEmpty ? nil : trimmedQuery,
            matchedCount: limited.count
        )
        return limited
    }

    func get(id: UUID?, subjectId: String?, reason: String?) throws -> SensitiveDataEntry {
        guard let id else {
            throw SensitiveDataRepositoryError.missingParameter("id")
        }
        let trimmedSubjectId = try required(subjectId, parameter: "subjectId")
        let trimmedReason = try required(reason, parameter: "reason")

        var store = loadStore()
        guard let index = store.entries.firstIndex(where: { $0.id == id }) else {
            throw SensitiveDataRepositoryError.invalidParameter("Sensitive data not found")
        }

        var entry = store.entries[index]
        entry.usageHistory.append(
            SensitiveDataUsageEntry(
                chatId: trimmedSubjectId,
                subjectId: trimmedSubjectId,
                subjectTitle: nil,
                purpose: trimmedReason
            )
        )
        entry.updatedAt = Date()
        store.entries[index] = entry
        store.audits.insert(
            SensitiveDataAuditEntry(
                action: .get,
                subjectId: trimmedSubjectId,
                reason: trimmedReason,
                key: entry.key,
                entryId: entry.id
            ),
            at: 0
        )
        try persist(store)
        return entry
    }

    func get(key: String?, subjectId: String?, reason: String?) throws -> SensitiveDataEntry {
        let trimmedKey = normalizedKey(key)
        if trimmedKey.isEmpty {
            throw SensitiveDataRepositoryError.missingParameter("key")
        }
        let trimmedSubjectId = try required(subjectId, parameter: "subjectId")
        let trimmedReason = try required(reason, parameter: "reason")

        var store = loadStore()
        guard let index = store.entries.firstIndex(where: { $0.key == trimmedKey }) else {
            throw SensitiveDataRepositoryError.invalidParameter("Sensitive data not found")
        }

        var entry = store.entries[index]
        entry.usageHistory.append(
            SensitiveDataUsageEntry(
                chatId: trimmedSubjectId,
                subjectId: trimmedSubjectId,
                subjectTitle: nil,
                purpose: trimmedReason
            )
        )
        entry.updatedAt = Date()
        store.entries[index] = entry
        store.audits.insert(
            SensitiveDataAuditEntry(
                action: .get,
                subjectId: trimmedSubjectId,
                reason: trimmedReason,
                key: entry.key,
                entryId: entry.id
            ),
            at: 0
        )
        try persist(store)
        return entry
    }

    func save(
        key: String?,
        label: String?,
        kind: String?,
        value: String?,
        allowedChats: [String]?,
        subjectId: String?,
        reason: String?
    ) throws -> SaveResult {
        let trimmedKey = normalizedKey(key)
        if trimmedKey.isEmpty {
            throw SensitiveDataRepositoryError.missingParameter("key")
        }

        let trimmedSubjectId = try required(subjectId, parameter: "subjectId")
        let trimmedReason = try required(reason, parameter: "reason")
        let trimmedLabel = try required(label, parameter: "label")
        let trimmedKind = try required(kind, parameter: "kind")
        let trimmedValue = try required(value, parameter: "value")
        let normalizedAllowedChats = normalizedStringArray(allowedChats)

        var store = loadStore()
        let now = Date()

        if let index = store.entries.firstIndex(where: { $0.key == trimmedKey }) {
            let existing = store.entries[index]
            let updatedEntry = SensitiveDataEntry(
                id: existing.id,
                key: trimmedKey,
                label: trimmedLabel,
                kind: trimmedKind,
                value: trimmedValue,
                allowedChats: normalizedAllowedChats,
                usageHistory: existing.usageHistory,
                createdAt: existing.createdAt,
                updatedAt: now
            )
            store.entries[index] = updatedEntry
            store.audits.insert(
                SensitiveDataAuditEntry(
                    action: .save,
                    subjectId: trimmedSubjectId,
                    reason: trimmedReason,
                    key: updatedEntry.key,
                    entryId: updatedEntry.id
                ),
                at: 0
            )
            try persist(store)
            return SaveResult(entry: updatedEntry, created: false, updated: true)
        }

        let entry = SensitiveDataEntry(
            id: UUID(),
            key: trimmedKey,
            label: trimmedLabel,
            kind: trimmedKind,
            value: trimmedValue,
            allowedChats: normalizedAllowedChats,
            usageHistory: [],
            createdAt: now,
            updatedAt: now
        )
        store.entries.append(entry)
        store.audits.insert(
            SensitiveDataAuditEntry(
                action: .save,
                subjectId: trimmedSubjectId,
                reason: trimmedReason,
                key: entry.key,
                entryId: entry.id
            ),
            at: 0
        )
        try persist(store)
        return SaveResult(entry: entry, created: true, updated: false)
    }

    func update(
        id: UUID?,
        key: String?,
        label: String?,
        kind: String?,
        value: String?,
        allowedChats: [String]?,
        subjectId: String?,
        reason: String?
    ) throws -> SensitiveDataEntry {
        let index = try resolveIndex(id: id, key: key)
        let trimmedSubjectId = try required(subjectId, parameter: "subjectId")
        let trimmedReason = try required(reason, parameter: "reason")
        var store = loadStore()
        var entry = store.entries[index]

        if let key {
            let trimmed = normalizedKey(key)
            if trimmed.isEmpty {
                throw SensitiveDataRepositoryError.missingParameter("key")
            }
            if trimmed != entry.key, store.entries.contains(where: { $0.key == trimmed && $0.id != entry.id }) {
                throw SensitiveDataRepositoryError.invalidParameter("Sensitive data key already exists")
            }
            entry.key = trimmed
        }

        if let label {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                entry.label = trimmed
            }
        }

        if let kind {
            let trimmed = kind.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                entry.kind = trimmed
            }
        }

        if let value {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                entry.value = trimmed
            }
        }

        if let allowedChats {
            entry.allowedChats = normalizedStringArray(allowedChats)
        }

        entry.updatedAt = Date()
        store.entries[index] = entry
        store.audits.insert(
            SensitiveDataAuditEntry(
                action: .update,
                subjectId: trimmedSubjectId,
                reason: trimmedReason,
                key: entry.key,
                entryId: entry.id
            ),
            at: 0
        )
        try persist(store)
        return entry
    }

    func delete(id: UUID?, subjectId: String?, reason: String?) throws -> Bool {
        guard let id else {
            throw SensitiveDataRepositoryError.missingParameter("id")
        }
        let trimmedSubjectId = try required(subjectId, parameter: "subjectId")
        let trimmedReason = try required(reason, parameter: "reason")

        var store = loadStore()
        let originalCount = store.entries.count
        let deletedEntry = store.entries.first(where: { $0.id == id })
        store.entries.removeAll { $0.id == id }
        guard store.entries.count != originalCount else {
            return false
        }
        store.audits.insert(
            SensitiveDataAuditEntry(
                action: .delete,
                subjectId: trimmedSubjectId,
                reason: trimmedReason,
                key: deletedEntry?.key,
                entryId: deletedEntry?.id
            ),
            at: 0
        )
        try persist(store)
        return true
    }

    func delete(key: String?, subjectId: String?, reason: String?) throws -> Bool {
        let trimmedKey = normalizedKey(key)
        if trimmedKey.isEmpty {
            throw SensitiveDataRepositoryError.missingParameter("key")
        }
        let trimmedSubjectId = try required(subjectId, parameter: "subjectId")
        let trimmedReason = try required(reason, parameter: "reason")

        var store = loadStore()
        let originalCount = store.entries.count
        let deletedEntry = store.entries.first(where: { $0.key == trimmedKey })
        store.entries.removeAll { $0.key == trimmedKey }
        guard store.entries.count != originalCount else {
            return false
        }
        store.audits.insert(
            SensitiveDataAuditEntry(
                action: .delete,
                subjectId: trimmedSubjectId,
                reason: trimmedReason,
                key: deletedEntry?.key ?? trimmedKey,
                entryId: deletedEntry?.id
            ),
            at: 0
        )
        try persist(store)
        return true
    }

    private func resolveIndex(id: UUID?, key: String?) throws -> Int {
        let store = loadStore()
        if let id, let index = store.entries.firstIndex(where: { $0.id == id }) {
            return index
        }

        let trimmedKey = normalizedKey(key)
        if !trimmedKey.isEmpty, let index = store.entries.firstIndex(where: { $0.key == trimmedKey }) {
            return index
        }

        if id == nil, trimmedKey.isEmpty {
            throw SensitiveDataRepositoryError.missingParameter("id or key")
        }

        throw SensitiveDataRepositoryError.invalidParameter("Sensitive data not found")
    }

    private func loadStore() -> Store {
        guard let data = try? store.loadData() else {
            return Store(entries: [], audits: [])
        }

        if let decoded = try? JSONDecoder().decode(Store.self, from: data) {
            return decoded
        }

        let legacyEntries = (try? JSONDecoder().decode([SensitiveDataEntry].self, from: data)) ?? []
        return Store(entries: legacyEntries, audits: [])
    }

    private func persist(_ storeValue: Store) throws {
        guard let data = try? JSONEncoder().encode(storeValue) else {
            throw SensitiveDataRepositoryError.invalidParameter("Unable to encode sensitive data entries")
        }
        try store.saveData(data)
        NotificationCenter.default.post(name: .sensitiveDataRepositoryDidChange, object: nil)
    }

    private func recordAudit(
        action: SensitiveDataAuditAction,
        subjectId: String,
        reason: String,
        query: String?,
        matchedCount: Int?,
        key: String? = nil,
        entryId: UUID? = nil
    ) throws {
        var store = loadStore()
        store.audits.insert(
            SensitiveDataAuditEntry(
                action: action,
                subjectId: subjectId,
                reason: reason,
                key: key,
                entryId: entryId,
                query: normalizedOptional(query),
                matchedCount: matchedCount
            ),
            at: 0
        )
        try persist(store)
    }

    private func searchResults(query: String?, limit: Int) -> [SensitiveDataSearchResult] {
        let trimmedQuery = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let store = loadStore()

        let ranked: [SensitiveDataSearchResult]
        if trimmedQuery.isEmpty {
            ranked = store.entries
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(max(1, limit))
                .map { SensitiveDataSearchResult(entry: $0, score: 1) }
        } else {
            ranked = store.entries
                .map { entry -> SensitiveDataSearchResult in
                    let score = TextSimilarity.bestScore(
                        query: trimmedQuery,
                        candidates: [
                            entry.key,
                            entry.label,
                            entry.kind,
                            entry.value,
                            entry.allowedChats.joined(separator: " ")
                        ]
                    )
                    return SensitiveDataSearchResult(entry: entry, score: score)
                }
                .sorted {
                    if $0.score == $1.score {
                        return $0.entry.updatedAt > $1.entry.updatedAt
                    }
                    return $0.score > $1.score
                }
        }

        return Array(ranked.prefix(max(1, limit)))
    }

    private func normalizedKey(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func required(_ value: String?, parameter: String) throws -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw SensitiveDataRepositoryError.missingParameter(parameter)
        }
        return trimmed
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedStringArray(_ values: [String]?) -> [String] {
        Array(
            Set(
                (values ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }
}
