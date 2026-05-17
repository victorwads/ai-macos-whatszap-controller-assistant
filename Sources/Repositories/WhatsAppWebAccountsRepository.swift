import Foundation

enum WhatsAppWebAccountsRepositoryError: LocalizedError {
    case missingParameter(String)

    var errorDescription: String? {
        switch self {
        case .missingParameter(let name):
            return "Missing parameter: \(name)"
        }
    }
}

actor WhatsAppWebAccountsRepository {
    static let shared = WhatsAppWebAccountsRepository()

    private let defaults: UserDefaults
    private let storageKey = "whatsappWebAccounts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func list() -> [WhatsAppWebAccount] {
        loadAll().sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func create(name: String?) throws -> WhatsAppWebAccount {
        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw WhatsAppWebAccountsRepositoryError.missingParameter("name")
        }

        var accounts = loadAll()
        let account = WhatsAppWebAccount(
            id: UUID(),
            name: trimmedName,
            profileIdentifier: UUID(),
            createdAt: Date()
        )
        accounts.append(account)
        persistAll(accounts)
        return account
    }

    func delete(id: UUID) -> Bool {
        var accounts = loadAll()
        let originalCount = accounts.count
        accounts.removeAll { $0.id == id }
        guard accounts.count != originalCount else {
            return false
        }

        persistAll(accounts)
        return true
    }

    private func loadAll() -> [WhatsAppWebAccount] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        return (try? JSONDecoder().decode([WhatsAppWebAccount].self, from: data)) ?? []
    }

    private func persistAll(_ accounts: [WhatsAppWebAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }
}
