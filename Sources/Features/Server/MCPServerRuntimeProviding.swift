import Foundation

@MainActor
protocol MCPServerRuntimeProviding {
    func assistantName() -> String
    func speechLanguage() -> String
    func speechVoiceIdentifier() -> String?
    func speechRate() -> Float
    func applyMCPSendMessagePrefixIfNeeded(_ text: String) -> String
    func refreshPendingClientAskCount() async
    func beginClientPromptWait() async -> UUID
    func endClientPromptWait(id: UUID) async
    func pendingClientPromptWaitCount() async -> Int
    func submitClientPrompt(_ text: String) async
    func consumeClientPrompt() async -> String?
    func sendMessageViaScheduler(_ text: String, to conversationId: String) async throws
    func ensureChatLoaded(chatId: String, reason: String) async
    func isBlocked(_ conversationName: String) -> Bool
    func appendLog(_ message: String, level: LogLevel)
}
