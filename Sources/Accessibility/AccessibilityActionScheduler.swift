import Foundation

enum AccessibilityActionPriority: Int, Comparable {
    case background = 0
    case userInitiated = 10
    case critical = 100

    static func < (lhs: AccessibilityActionPriority, rhs: AccessibilityActionPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

actor AccessibilityActionScheduler {
    typealias Action = @Sendable () async throws -> Void

    private struct QueuedAction {
        let id: UUID
        let priority: AccessibilityActionPriority
        let enqueuedAt: UInt64
        let action: Action
    }

    private var queue: [QueuedAction] = []
    private var isRunning = false

    func enqueue(priority: AccessibilityActionPriority, action: @escaping Action) {
        let item = QueuedAction(id: UUID(), priority: priority, enqueuedAt: DispatchTime.now().uptimeNanoseconds, action: action)
        queue.append(item)
        queue.sort { left, right in
            if left.priority != right.priority {
                return left.priority > right.priority
            }
            return left.enqueuedAt < right.enqueuedAt
        }

        if !isRunning {
            isRunning = true
            Task { [weak self] in
                guard let self else { return }
                await self.drain()
            }
        }
    }

    func cancelAll(where shouldCancel: (AccessibilityActionPriority) -> Bool) {
        queue.removeAll { shouldCancel($0.priority) }
    }

    private func drain() async {
        while true {
            guard !queue.isEmpty else {
                isRunning = false
                return
            }

            let next = queue.removeFirst()
            do {
                try await next.action()
            } catch {
                // Intentionally ignore action failures at the scheduler level.
                // Call sites are responsible for logging/handling.
            }
        }
    }
}

