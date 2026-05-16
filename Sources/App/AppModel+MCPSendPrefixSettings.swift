import Combine
import Foundation

extension AppModel {
    func assistantNameForMCP() -> String {
        mcpSendPrefixSettings.assistantName
    }

    func formattedMCPSendMessages(for texts: [String]) -> [String] {
        mcpSendPrefixSettings.formattedMessages(for: texts)
    }
}
