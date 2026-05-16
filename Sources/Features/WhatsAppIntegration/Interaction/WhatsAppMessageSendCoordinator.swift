import Foundation

@MainActor
final class WhatsAppMessageSendCoordinator {
    private let accessibility: AccessibilityService
    private let accessibilityScheduler: AccessibilityActionScheduler
    private let parser: WhatsAppAppParser
    private let interactor: WhatsAppInteractor
    private let inputLockSettings: InputLockSettingsModel
    private let isPolling: () -> Bool
    private let stopPolling: () -> Void
    private let startPolling: () -> Void
    private let resolveConversation: (String) -> ConversationSummary?
    private let isBlocked: (String) -> Bool
    private let openConversationAndCapture: (ConversationSummary) async throws -> WhatsAppSnapshot
    private let updateSelectedChatState: (WhatsAppScreenState, ConversationSummary) -> Void
    private let appendLog: (String, LogLevel) -> Void

    init(
        accessibility: AccessibilityService,
        accessibilityScheduler: AccessibilityActionScheduler,
        parser: WhatsAppAppParser,
        interactor: WhatsAppInteractor,
        inputLockSettings: InputLockSettingsModel,
        isPolling: @escaping () -> Bool,
        stopPolling: @escaping () -> Void,
        startPolling: @escaping () -> Void,
        resolveConversation: @escaping (String) -> ConversationSummary?,
        isBlocked: @escaping (String) -> Bool,
        openConversationAndCapture: @escaping (ConversationSummary) async throws -> WhatsAppSnapshot,
        updateSelectedChatState: @escaping (WhatsAppScreenState, ConversationSummary) -> Void,
        appendLog: @escaping (String, LogLevel) -> Void
    ) {
        self.accessibility = accessibility
        self.accessibilityScheduler = accessibilityScheduler
        self.parser = parser
        self.interactor = interactor
        self.inputLockSettings = inputLockSettings
        self.isPolling = isPolling
        self.stopPolling = stopPolling
        self.startPolling = startPolling
        self.resolveConversation = resolveConversation
        self.isBlocked = isBlocked
        self.openConversationAndCapture = openConversationAndCapture
        self.updateSelectedChatState = updateSelectedChatState
        self.appendLog = appendLog
    }

    func sendMessageViaScheduler(_ text: String, to conversationId: String) async throws {
        await accessibilityScheduler.cancelAll { $0 == .background }

        let resumePollingAfterSend = isPolling()
        if resumePollingAfterSend {
            stopPolling()
        }

        defer {
            if resumePollingAfterSend {
                startPolling()
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                await self.accessibilityScheduler.enqueue(priority: .critical) {
                    do {
                        try await self.sendMessage(text, to: conversationId)
                        continuation.resume(returning: ())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func sendMessage(_ text: String, to conversationId: String) async throws {
        guard let conversation = resolveConversation(conversationId) else {
            throw MCPServerError.invalidParameter("chatId")
        }

        guard !isBlocked(conversation.name) else {
            throw MCPServerError.invalidRequest
        }

        let trimmedMessage = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw MCPServerError.invalidParameter("text")
        }

        let shouldLockInput = inputLockSettings.isEnabled
        if shouldLockInput {
            // Lock before selecting the chat so the user cannot change focus mid-send.
            accessibility.lockUserInputForSend(seconds: 5)
        }
        defer {
            if shouldLockInput {
                accessibility.unlockUserInputAfterSend()
            }
        }

        let snapshot = try await openConversationAndCapture(conversation)
        let screenState = parser.parse(snapshot: snapshot, messageLimit: 10)
        guard screenState.selectedChatName == conversation.name else {
            throw AccessibilityError.actionFailed(-1)
        }

        updateSelectedChatState(screenState, conversation)

        appendLog("Sending message to \(conversation.name)…", .info)
        try interactor.sendMessage(trimmedMessage, using: accessibility)
        appendLog("Sent message to \(conversation.name).", .info)
    }
}
