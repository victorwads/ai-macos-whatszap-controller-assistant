import Foundation

enum MessageDirection: String, Equatable {
    case incoming
    case outgoing
    case unknown
}

enum MessageKind: String, Equatable {
    case text
    case voice
    case image
    case document
    case deleted
    case unknown
}

enum MessageStatus: String, Equatable {
    case sent
    case delivered
    case read
    case unknown
}

struct Message: Identifiable, Equatable {
    let id: String
    let chatId: String
    let direction: MessageDirection
    let kind: MessageKind
    let text: String?
    let durationSeconds: Double?
    let timestamp: Date?
    let status: MessageStatus
    let rawAccessibilityText: String
}
