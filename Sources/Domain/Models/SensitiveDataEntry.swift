import Foundation

struct SensitiveDataUsageEntry: Codable, Equatable {
    let id: UUID
    let timestamp: Date
    var chatId: String
    var subjectId: String?
    var subjectTitle: String?
    var purpose: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        chatId: String,
        subjectId: String? = nil,
        subjectTitle: String? = nil,
        purpose: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.chatId = chatId
        self.subjectId = subjectId
        self.subjectTitle = subjectTitle
        self.purpose = purpose
    }
}

enum SensitiveDataAuditAction: String, Codable, CaseIterable {
    case save
    case update
    case delete
    case list
    case search
    case get
}

struct SensitiveDataAuditEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    var action: SensitiveDataAuditAction
    var subjectId: String
    var reason: String
    var key: String?
    var entryId: UUID?
    var query: String?
    var matchedCount: Int?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: SensitiveDataAuditAction,
        subjectId: String,
        reason: String,
        key: String? = nil,
        entryId: UUID? = nil,
        query: String? = nil,
        matchedCount: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.subjectId = subjectId
        self.reason = reason
        self.key = key
        self.entryId = entryId
        self.query = query
        self.matchedCount = matchedCount
    }
}

struct SensitiveDataEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var key: String
    var label: String
    var kind: String
    var value: String
    var allowedChats: [String]
    var usageHistory: [SensitiveDataUsageEntry]
    let createdAt: Date
    var updatedAt: Date
}

struct SensitiveDataSearchResult: Codable, Equatable {
    let entry: SensitiveDataEntry
    let score: Double
}

extension SensitiveDataEntry {
    var maskedValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > 4 else { return String(repeating: "*", count: max(4, trimmed.count)) }

        let prefix = trimmed.prefix(2)
        let suffix = trimmed.suffix(2)
        let maskCount = max(4, trimmed.count - 4)
        return "\(prefix)\(String(repeating: "*", count: maskCount))\(suffix)"
    }

    var lastUsedAt: Date? {
        usageHistory.last?.timestamp
    }
}
