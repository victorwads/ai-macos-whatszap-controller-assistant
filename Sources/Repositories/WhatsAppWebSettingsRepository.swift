import Foundation

@MainActor
final class WhatsAppWebSettingsRepository {
    static let shared = WhatsAppWebSettingsRepository()

    private let defaults: UserDefaults
    private let userAgentKey = "whatsAppWeb.customUserAgent"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadCustomUserAgent(defaultValue: String) -> String {
        let storedValue = defaults.string(forKey: userAgentKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let storedValue, !storedValue.isEmpty else {
            return defaultValue
        }
        return storedValue
    }

    func saveCustomUserAgent(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmedValue, forKey: userAgentKey)
    }
}
