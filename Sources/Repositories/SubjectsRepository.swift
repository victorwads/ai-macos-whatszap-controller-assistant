import Foundation

enum SubjectsRepositoryError: LocalizedError {
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

actor SubjectsRepository {
    static let shared = SubjectsRepository()

    private let defaults: UserDefaults
    private let storageKey = "subjects.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func listAll() -> [SubjectEntry] {
        loadAll()
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func listActive() -> [SubjectEntry] {
        listAll().filter { $0.status == .active }
    }

    func get(id: UUID?) throws -> SubjectEntry {
        guard let id else {
            throw SubjectsRepositoryError.missingParameter("id")
        }
        guard let found = loadAll().first(where: { $0.id == id }) else {
            throw SubjectsRepositoryError.invalidParameter("Subject not found")
        }
        return found
    }

    func create(
        title: String?,
        details: String?,
        priority: Int?,
        participants: [String]?,
        nextSteps: [String]?,
        whatsappChatId: String?,
        gmailThreadId: String?,
        calendarEventId: String?
    ) throws -> SubjectEntry {
        let trimmedTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            throw SubjectsRepositoryError.missingParameter("title")
        }

        var all = loadAll()
        let now = Date()
        let entry = SubjectEntry(
            id: UUID(),
            title: trimmedTitle,
            details: details?.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .active,
            priority: max(0, priority ?? 0),
            participants: (participants ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            nextSteps: (nextSteps ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            whatsappChatId: whatsappChatId?.trimmingCharacters(in: .whitespacesAndNewlines),
            whatsappAfterMessageId: nil,
            gmailThreadId: gmailThreadId?.trimmingCharacters(in: .whitespacesAndNewlines),
            calendarEventId: calendarEventId?.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            updatedAt: now
        )
        all.append(entry)
        persistAll(all)
        return entry
    }

    func update(
        id: UUID?,
        title: String?,
        details: String?,
        status: SubjectStatus?,
        priority: Int?,
        participants: [String]?,
        nextSteps: [String]?,
        whatsappChatId: String?,
        whatsappAfterMessageId: String?,
        gmailThreadId: String?,
        calendarEventId: String?
    ) throws -> SubjectEntry {
        guard let id else {
            throw SubjectsRepositoryError.missingParameter("id")
        }

        var all = loadAll()
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            throw SubjectsRepositoryError.invalidParameter("Subject not found")
        }

        var subject = all[index]
        if let title {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                subject.title = trimmedTitle
            }
        }
        if let details {
            let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
            subject.details = trimmed.isEmpty ? nil : trimmed
        }
        if let status {
            subject.status = status
        }
        if let priority {
            subject.priority = max(0, priority)
        }
        if let participants {
            subject.participants = participants.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let nextSteps {
            subject.nextSteps = nextSteps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let whatsappChatId {
            let trimmed = whatsappChatId.trimmingCharacters(in: .whitespacesAndNewlines)
            subject.whatsappChatId = trimmed.isEmpty ? nil : trimmed
        }
        if let whatsappAfterMessageId {
            let trimmed = whatsappAfterMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
            subject.whatsappAfterMessageId = trimmed.isEmpty ? nil : trimmed
        }
        if let gmailThreadId {
            let trimmed = gmailThreadId.trimmingCharacters(in: .whitespacesAndNewlines)
            subject.gmailThreadId = trimmed.isEmpty ? nil : trimmed
        }
        if let calendarEventId {
            let trimmed = calendarEventId.trimmingCharacters(in: .whitespacesAndNewlines)
            subject.calendarEventId = trimmed.isEmpty ? nil : trimmed
        }

        subject.updatedAt = Date()
        all[index] = subject
        persistAll(all)
        return subject
    }

    func finish(id: UUID?) throws -> SubjectEntry {
        try update(
            id: id,
            title: nil,
            details: nil,
            status: .finished,
            priority: nil,
            participants: nil,
            nextSteps: nil,
            whatsappChatId: nil,
            whatsappAfterMessageId: nil,
            gmailThreadId: nil,
            calendarEventId: nil
        )
    }

    func delete(id: UUID?) throws -> Bool {
        guard let id else {
            throw SubjectsRepositoryError.missingParameter("id")
        }

        var all = loadAll()
        let originalCount = all.count
        all.removeAll { $0.id == id }
        guard all.count != originalCount else {
            return false
        }
        persistAll(all)
        return true
    }

    private func loadAll() -> [SubjectEntry] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([SubjectEntry].self, from: data)) ?? []
    }

    private func persistAll(_ subjects: [SubjectEntry]) {
        guard let data = try? JSONEncoder().encode(subjects) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}

