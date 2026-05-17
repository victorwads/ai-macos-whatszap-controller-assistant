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
    private let storageKey = "subjects.v2"

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
        summary: String?,
        initialRequest: String?,
        stopCondition: String?,
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

        let trimmedSummary = (summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSummary.isEmpty {
            throw SubjectsRepositoryError.missingParameter("summary")
        }

        let trimmedInitialRequest = (initialRequest ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedInitialRequest.isEmpty {
            throw SubjectsRepositoryError.missingParameter("initialRequest")
        }

        let trimmedStopCondition = (stopCondition ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedStopCondition.isEmpty {
            throw SubjectsRepositoryError.missingParameter("stopCondition")
        }

        var all = loadAll()
        let now = Date()
        let entry = SubjectEntry(
            id: UUID(),
            title: trimmedTitle,
            summary: trimmedSummary,
            initialRequest: trimmedInitialRequest,
            stopCondition: trimmedStopCondition,
            details: normalizedOptional(details),
            status: .active,
            priority: max(0, priority ?? 0),
            participants: (participants ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            nextSteps: (nextSteps ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            eventLog: [],
            whatsappChatId: normalizedOptional(whatsappChatId),
            whatsappAfterMessageId: nil,
            gmailThreadId: normalizedOptional(gmailThreadId),
            calendarEventId: normalizedOptional(calendarEventId),
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
        summary: String?,
        stopCondition: String?,
        details: String?,
        priority: Int?,
        participants: [String]?,
        nextSteps: [String]?,
        appendUpdatesLog: [String]?,
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
        if let summary {
            let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSummary.isEmpty {
                subject.summary = trimmedSummary
            }
        }
        if let stopCondition {
            let trimmedStopCondition = stopCondition.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedStopCondition.isEmpty {
                subject.stopCondition = trimmedStopCondition
            }
        }
        if let details {
            let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
            subject.details = trimmed.isEmpty ? nil : trimmed
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
        if let appendUpdatesLog {
            appendUpdates(appendUpdatesLog, to: &subject)
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

    func resolve(id: UUID?, reason: String?) throws -> SubjectEntry {
        try close(
            id: id,
            status: .resolved,
            reason: reason
        )
    }

    func cancel(id: UUID?, reason: String?) throws -> SubjectEntry {
        try close(
            id: id,
            status: .canceled,
            reason: reason
        )
    }

    private func close(id: UUID?, status: SubjectStatus, reason: String?) throws -> SubjectEntry {
        guard let id else {
            throw SubjectsRepositoryError.missingParameter("id")
        }

        let trimmedReason = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedReason.isEmpty {
            throw SubjectsRepositoryError.missingParameter("reason")
        }

        var all = loadAll()
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            throw SubjectsRepositoryError.invalidParameter("Subject not found")
        }

        var subject = all[index]
        try applyTerminalStatus(&subject, status: status, reason: trimmedReason)
        all[index] = subject
        persistAll(all)
        return subject
    }

    private func applyTerminalStatus(_ subject: inout SubjectEntry, status: SubjectStatus, reason: String?) throws {
        let trimmedReason = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedReason.isEmpty {
            throw SubjectsRepositoryError.missingParameter("reason")
        }

        subject.status = status
        let actionLabel: String = {
            switch status {
            case .resolved:
                return "resolved"
            case .canceled:
                return "canceled"
            case .active:
                return "updated"
            }
        }()
        subject.eventLog.append(
            EventEntry(
                timestamp: Date(),
                description: "Subject \(actionLabel). Reason: \(trimmedReason)",
                source: "manual"
            )
        )
        subject.updatedAt = Date()
    }

    private func appendUpdates(_ updates: [String], to subject: inout SubjectEntry) {
        var existingDescriptions = Set(subject.eventLog.map(\.description))

        for update in updates {
            let trimmed = update.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !existingDescriptions.contains(trimmed) else { continue }

            subject.eventLog.append(
                EventEntry(
                    description: trimmed,
                    source: "assistant",
                    author: "assistant"
                )
            )
            existingDescriptions.insert(trimmed)
        }
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func loadAll() -> [SubjectEntry] {
        if let data = defaults.data(forKey: storageKey),
           let entries = try? JSONDecoder().decode([SubjectEntry].self, from: data) {
            return entries.map { migrate($0) }
        }

        if let migrated = loadAllFromV1Fallback() {
            // Persist as v2 so we only migrate once.
            persistAll(migrated)
            return migrated
        }

        return []
    }

    private struct SubjectEntryV1: Codable {
        let id: UUID
        var title: String
        var summary: String
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
    }

    private func loadAllFromV1Fallback() -> [SubjectEntry]? {
        let v1Key = "subjects.v1"
        guard let data = defaults.data(forKey: v1Key) else { return nil }
        guard let entries = try? JSONDecoder().decode([SubjectEntryV1].self, from: data) else { return nil }

        let migrated: [SubjectEntry] = entries.map { old in
            SubjectEntry(
                id: old.id,
                title: old.title,
                summary: old.summary,
                initialRequest: old.summary,
                stopCondition: "",
                details: old.details,
                status: old.status,
                priority: old.priority,
                participants: old.participants,
                nextSteps: old.nextSteps,
                eventLog: old.eventLog,
                whatsappChatId: old.whatsappChatId,
                whatsappAfterMessageId: old.whatsappAfterMessageId,
                gmailThreadId: old.gmailThreadId,
                calendarEventId: old.calendarEventId,
                createdAt: old.createdAt,
                updatedAt: old.updatedAt
            )
        }

        return migrated.map { migrate($0) }
    }

    private func migrate(_ entry: SubjectEntry) -> SubjectEntry {
        var mutable = entry
        if mutable.summary.isEmpty {
            mutable.summary = "(Resumo não disponível - sujeito antigo)"
        }
        if mutable.initialRequest.isEmpty {
            mutable.initialRequest = "(Solicitacao inicial nao disponivel - sujeito antigo)"
        }
        if mutable.stopCondition.isEmpty {
            mutable.stopCondition = "(Condição de parada não disponível - sujeito antigo)"
        }
        if mutable.eventLog.isEmpty {
            mutable.eventLog = []
        }
        return mutable
    }

    private func persistAll(_ subjects: [SubjectEntry]) {
        guard let data = try? JSONEncoder().encode(subjects) else {
            return
        }
        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: .subjectsRepositoryDidChange, object: nil)
    }
}
