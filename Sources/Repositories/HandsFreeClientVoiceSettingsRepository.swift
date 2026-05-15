import Foundation

@MainActor
final class HandsFreeClientVoiceSettingsRepository {
    static let shared = HandsFreeClientVoiceSettingsRepository()

    private let defaults: UserDefaults
    private let storageKey = "handsFreeClientVoiceEnabled"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(defaultValue: Bool = true) -> Bool {
        if defaults.object(forKey: storageKey) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: storageKey)
    }

    func save(_ enabled: Bool) {
        defaults.set(enabled, forKey: storageKey)
    }
}

