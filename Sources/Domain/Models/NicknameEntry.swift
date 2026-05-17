import Foundation

struct NicknameEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let originalName: String
    let nickname: String
    let chatId: String?
    let createdAt: Date

    init(id: UUID, originalName: String, nickname: String, chatId: String? = nil, createdAt: Date) {
        self.id = id
        self.originalName = originalName
        self.nickname = nickname
        self.chatId = chatId
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case originalName
        case chatName
        case nickname
        case chatId
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nickname = try container.decode(String.self, forKey: .nickname)
        chatId = try container.decodeIfPresent(String.self, forKey: .chatId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        originalName = try container.decodeIfPresent(String.self, forKey: .originalName)
            ?? container.decode(String.self, forKey: .chatName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(originalName, forKey: .originalName)
        try container.encode(nickname, forKey: .nickname)
        try container.encodeIfPresent(chatId, forKey: .chatId)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
