import AVFoundation
import Foundation

@MainActor
final class AppModelMCPRuntimeAdapter: MCPServerRuntimeProviding {
    private weak var appModel: AppModel?

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    func assistantInstructions() -> String {
        appModel?.assistantInstructions ?? ""
    }

    func speechLanguage() -> String {
        appModel?.speechLanguage ?? "pt-BR"
    }

    func speechVoiceIdentifier() -> String? {
        appModel?.speechVoiceIdentifier
    }

    func speechRate() -> Float {
        appModel?.speechRate ?? AVSpeechUtteranceDefaultSpeechRate
    }

    func applyMCPSendMessagePrefixIfNeeded(_ text: String) -> String {
        appModel?.applyMCPSendMessagePrefixIfNeeded(text) ?? text
    }

    func refreshPendingClientAskCount() async {
        await appModel?.refreshPendingClientAskCount()
    }

    func sendMessageViaScheduler(_ text: String, to conversationId: String) async throws {
        guard let appModel else { throw CancellationError() }
        try await appModel.sendMessageViaScheduler(text, to: conversationId)
    }

    func ensureChatLoaded(chatId: String, reason: String) async {
        await appModel?.ensureChatLoaded(chatId: chatId, reason: reason)
    }

    func isBlocked(_ conversationName: String) -> Bool {
        appModel?.isBlocked(conversationName) ?? false
    }

    func appendLog(_ message: String, level: LogLevel) {
        appModel?.appendLog(message, level: level)
    }
}
