import Foundation

@MainActor
final class DebugTreeFavoritesRepository {
    static let shared = DebugTreeFavoritesRepository()

    private let defaults: UserDefaults
    private let storageKey = "debugTreeFavoritesV1"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [String: [Int]] {
        if let data = defaults.data(forKey: storageKey) {
            if let decoded = try? JSONDecoder().decode([String: [Int]].self, from: data) {
                return decoded
            }
            return [:]
        }

        if let legacyString = defaults.string(forKey: storageKey) {
            let data = Data(legacyString.utf8)
            if let decoded = try? JSONDecoder().decode([String: [Int]].self, from: data) {
                defaults.set(data, forKey: storageKey)
                return decoded
            }
        }

        return [:]
    }

    func save(_ favorites: [String: [Int]]) {
        guard let data = try? JSONEncoder().encode(favorites) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
