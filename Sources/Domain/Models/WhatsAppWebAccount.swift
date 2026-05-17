import Foundation

struct WhatsAppWebAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let profileIdentifier: UUID
    let createdAt: Date
    var isAutoStart: Bool

    init(
        id: UUID,
        name: String,
        profileIdentifier: UUID,
        createdAt: Date,
        isAutoStart: Bool = false
    ) {
        self.id = id
        self.name = name
        self.profileIdentifier = profileIdentifier
        self.createdAt = createdAt
        self.isAutoStart = isAutoStart
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case profileIdentifier
        case createdAt
        case isAutoStart
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        profileIdentifier = try container.decode(UUID.self, forKey: .profileIdentifier)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isAutoStart = try container.decodeIfPresent(Bool.self, forKey: .isAutoStart) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(profileIdentifier, forKey: .profileIdentifier)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isAutoStart, forKey: .isAutoStart)
    }
}
