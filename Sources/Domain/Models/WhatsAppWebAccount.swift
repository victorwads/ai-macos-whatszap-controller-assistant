import Foundation

struct WhatsAppWebAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let profileIdentifier: UUID
    let createdAt: Date
}
