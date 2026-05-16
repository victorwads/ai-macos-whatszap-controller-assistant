import Combine
import Foundation

extension AppModel {
    func applyMCPSendMessagePrefixIfNeeded(_ text: String) -> String {
        mcpSendPrefixSettings.applyPrefixIfNeeded(text)
    }
}
