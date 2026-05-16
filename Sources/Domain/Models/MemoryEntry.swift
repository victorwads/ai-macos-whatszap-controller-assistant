import Foundation

struct MemoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var key: String
    var content: String
    var tags: [String]
    let createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case title
        case content
        case tags
        case createdAt
        case updatedAt
    }

    init(
        id: UUID,
        key: String,
        content: String,
        tags: [String],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.key = key
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let decodedKey = try container.decodeIfPresent(String.self, forKey: .key)
            ?? container.decodeIfPresent(String.self, forKey: .title)
            ?? ""
        key = decodedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        content = try container.decode(String.self, forKey: .content)
        tags = (try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(key, forKey: .key)
        try container.encode(content, forKey: .content)
        try container.encode(tags, forKey: .tags)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
