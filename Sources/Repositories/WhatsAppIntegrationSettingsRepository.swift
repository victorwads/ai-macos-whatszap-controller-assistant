import Foundation

@MainActor
final class WhatsAppIntegrationSettingsRepository {
    static let shared = WhatsAppIntegrationSettingsRepository()

    private let defaults: UserDefaults
    private let modeKey = "whatsApp.integrationMode"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadMode(defaultValue: WhatsAppIntegrationMode) -> WhatsAppIntegrationMode {
        let raw = defaults.string(forKey: modeKey)
        return WhatsAppIntegrationMode(rawValue: raw ?? "") ?? defaultValue
    }

    func saveMode(_ mode: WhatsAppIntegrationMode) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }
}

