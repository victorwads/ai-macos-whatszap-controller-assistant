import Foundation

@MainActor
protocol MCPServerRuntimeProviding {
    func assistantInstructions() -> String
    func speechLanguage() -> String
    func speechVoiceIdentifier() -> String?
    func speechRate() -> Float
    func applyMCPSendMessagePrefixIfNeeded(_ text: String) -> String
    func refreshPendingClientAskCount() async
    func sendMessageViaScheduler(_ text: String, to conversationId: String) async throws
    func ensureChatLoaded(chatId: String, reason: String) async
    func isBlocked(_ conversationName: String) -> Bool
    func appendLog(_ message: String, level: LogLevel)
}
