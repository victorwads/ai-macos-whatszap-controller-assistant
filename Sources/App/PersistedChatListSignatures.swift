import Foundation

struct PersistedChatListSignatures: Codable, Equatable {
    var version: Int = 1
    var updatedAt: Date = Date()
    var signaturesByChatId: [String: String] = [:]
}

