import Foundation

@MainActor
final class MCPSendPrefixRepository {
    static let shared = MCPSendPrefixRepository()

    private let defaults: UserDefaults
    private let storageKey = "mcpSendMessagePrefix"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> String {
        defaults.string(forKey: storageKey) ?? ""
    }

    func save(_ value: String) {
        defaults.set(value, forKey: storageKey)
    }
}
