import Foundation

@MainActor
final class InputLockSettingsRepository {
    static let shared = InputLockSettingsRepository()

    private let defaults: UserDefaults
    private let storageKey = "experimentalInputLockEnabled"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Bool {
        defaults.bool(forKey: storageKey)
    }

    func save(_ enabled: Bool) {
        defaults.set(enabled, forKey: storageKey)
    }
}
