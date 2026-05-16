import Foundation

@MainActor
final class MCPSendPrefixRepository {
    static let shared = MCPSendPrefixRepository()

    private let defaults: UserDefaults
    private let storageKey = "mcpSendMessagePrefix"
    private let assistantNameKey = "mcpSendMessageAssistantName"
    private let signatureKey = "mcpSendMessageSignature"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> (assistantName: String, signature: String) {
        let assistantName = defaults.string(forKey: assistantNameKey)
        let signature = defaults.string(forKey: signatureKey)

        if assistantName != nil || signature != nil {
            return (
                assistantName: assistantName ?? "",
                signature: signature ?? ""
            )
        }

        return (
            assistantName: defaults.string(forKey: storageKey) ?? "",
            signature: ""
        )
    }

    func save(assistantName: String, signature: String) {
        defaults.set(assistantName, forKey: assistantNameKey)
        defaults.set(signature, forKey: signatureKey)
        defaults.set(assistantName, forKey: storageKey)
    }
}
