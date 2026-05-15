import Combine
import Foundation

extension AppModel {
    func loadMCPSendMessagePrefixSetting() {
        mcpSendMessagePrefix = MCPSendPrefixRepository.shared.load()

        $mcpSendMessagePrefix
            .dropFirst()
            .sink { [weak self] value in
                guard self != nil else { return }
                MCPSendPrefixRepository.shared.save(value)
            }
            .store(in: &cancellables)
    }

    func applyMCPSendMessagePrefixIfNeeded(_ text: String) -> String {
        let prefix = mcpSendMessagePrefix
        guard !prefix.isEmpty else { return text }
        return prefix + text
    }
}
