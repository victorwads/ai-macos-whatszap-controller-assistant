import Foundation

enum SubjectStatus: String, Codable, CaseIterable {
    case active
    case finished
}

struct SubjectEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var details: String?
    var status: SubjectStatus
    var priority: Int
    var participants: [String]
    var nextSteps: [String]

    var whatsappChatId: String?
    var whatsappAfterMessageId: String?
    var gmailThreadId: String?
    var calendarEventId: String?

    let createdAt: Date
    var updatedAt: Date
}

