import Foundation

enum SubjectStatus: String, Codable, CaseIterable {
    case active
    case resolved
    case canceled

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "active":
            self = .active
        case "finished", "resolved":
            self = .resolved
        case "canceled", "cancelled":
            self = .canceled
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid SubjectStatus value: \(rawValue)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .resolved:
            return "Resolved"
        case .canceled:
            return "Canceled"
        }
    }
}

struct SubjectEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var summary: String
    var initialRequest: String
    var stopCondition: String
    var details: String?
    var status: SubjectStatus
    var priority: Int
    var participants: [String]
    var nextSteps: [String]
    var eventLog: [EventEntry]

    var whatsappChatId: String?
    var whatsappAfterMessageId: String?
    var gmailThreadId: String?
    var calendarEventId: String?

    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        title: String,
        summary: String,
        initialRequest: String,
        stopCondition: String,
        details: String?,
        status: SubjectStatus,
        priority: Int,
        participants: [String],
        nextSteps: [String],
        eventLog: [EventEntry],
        whatsappChatId: String?,
        whatsappAfterMessageId: String?,
        gmailThreadId: String?,
        calendarEventId: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.initialRequest = initialRequest
        self.stopCondition = stopCondition
        self.details = details
        self.status = status
        self.priority = priority
        self.participants = participants
        self.nextSteps = nextSteps
        self.eventLog = eventLog
        self.whatsappChatId = whatsappChatId
        self.whatsappAfterMessageId = whatsappAfterMessageId
        self.gmailThreadId = gmailThreadId
        self.calendarEventId = calendarEventId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension SubjectEntry {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case initialRequest
        case stopCondition
        case details
        case status
        case priority
        case participants
        case nextSteps
        case eventLog
        case whatsappChatId
        case whatsappAfterMessageId
        case gmailThreadId
        case calendarEventId
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.initialRequest = try container.decode(String.self, forKey: .initialRequest)
        self.stopCondition = try container.decodeIfPresent(String.self, forKey: .stopCondition) ?? ""
        self.details = try container.decodeIfPresent(String.self, forKey: .details)
        self.status = try container.decode(SubjectStatus.self, forKey: .status)
        self.priority = try container.decode(Int.self, forKey: .priority)
        self.participants = try container.decodeIfPresent([String].self, forKey: .participants) ?? []
        self.nextSteps = try container.decodeIfPresent([String].self, forKey: .nextSteps) ?? []
        self.eventLog = try container.decodeIfPresent([EventEntry].self, forKey: .eventLog) ?? []
        self.whatsappChatId = try container.decodeIfPresent(String.self, forKey: .whatsappChatId)
        self.whatsappAfterMessageId = try container.decodeIfPresent(String.self, forKey: .whatsappAfterMessageId)
        self.gmailThreadId = try container.decodeIfPresent(String.self, forKey: .gmailThreadId)
        self.calendarEventId = try container.decodeIfPresent(String.self, forKey: .calendarEventId)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(initialRequest, forKey: .initialRequest)
        try container.encode(stopCondition, forKey: .stopCondition)
        try container.encodeIfPresent(details, forKey: .details)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(participants, forKey: .participants)
        try container.encode(nextSteps, forKey: .nextSteps)
        try container.encode(eventLog, forKey: .eventLog)
        try container.encodeIfPresent(whatsappChatId, forKey: .whatsappChatId)
        try container.encodeIfPresent(whatsappAfterMessageId, forKey: .whatsappAfterMessageId)
        try container.encodeIfPresent(gmailThreadId, forKey: .gmailThreadId)
        try container.encodeIfPresent(calendarEventId, forKey: .calendarEventId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

extension SubjectEntry {
    var terminalReason: String? {
        let prefixes = [
            "Subject resolved. Reason: ",
            "Subject canceled. Reason: "
        ]

        for event in eventLog.reversed() {
            for prefix in prefixes where event.description.hasPrefix(prefix) {
                let reason = String(event.description.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return reason.isEmpty ? nil : reason
            }
        }
        return nil
    }
}

struct EventEntry: Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let description: String
    let source: String?  // ex: "whatsapp", "gmail", "calendar", "manual"
    let author: String?

    init(id: UUID = UUID(), timestamp: Date = Date(), description: String, source: String? = nil, author: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.description = description
        self.source = source
        self.author = author
    }
}
