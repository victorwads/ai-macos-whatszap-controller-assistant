import Foundation

actor ClientPromptWaitRepository {
    static let shared = ClientPromptWaitRepository()

    private var activeWaitIDs: Set<UUID> = []
    private var pendingPrompt: String?

    func beginWait() -> UUID {
        let id = UUID()
        activeWaitIDs.insert(id)
        return id
    }

    func endWait(id: UUID) {
        activeWaitIDs.remove(id)
    }

    func pendingWaitCount() -> Int {
        activeWaitIDs.count
    }

    func submitPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        pendingPrompt = trimmed
    }

    func consumePrompt() -> String? {
        defer { pendingPrompt = nil }
        return pendingPrompt
    }
}
