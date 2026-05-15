import Foundation

@MainActor
final class AssistantInstructionsRepository {
    static let shared = AssistantInstructionsRepository()

    private let defaults: UserDefaults
    private let storageKey = "assistantInstructions"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(defaultValue: String) -> String {
        defaults.string(forKey: storageKey) ?? defaultValue
    }

    func save(_ value: String) {
        defaults.set(value, forKey: storageKey)
    }
}
