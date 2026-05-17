import Foundation

extension AppModel {
    func loadWhatsAppWebAccounts() async {
        let accounts = await whatsAppWebAccountsRepository.list()
        whatsAppWebAccounts = accounts
        whatsAppWebSessionStore.warmSessions(for: accounts)

        if let selectedWhatsAppWebAccountId,
           accounts.contains(where: { $0.id == selectedWhatsAppWebAccountId }) {
            return
        }

        selectedWhatsAppWebAccountId = accounts.first?.id
    }

    func addWhatsAppWebAccount(named name: String) async {
        do {
            let account = try await whatsAppWebAccountsRepository.create(name: name)
            whatsAppWebAccounts.append(account)
            whatsAppWebAccounts.sort { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            _ = whatsAppWebSessionStore.webView(for: account)
            selectedWhatsAppWebAccountId = account.id
            appendLog("Created WhatsApp Web account '\(account.name)'.")
        } catch {
            appendLog("Failed to create WhatsApp Web account: \(error.localizedDescription)", level: .error)
        }
    }

    func deleteWhatsAppWebAccount(id: UUID) async {
        let deleted = await whatsAppWebAccountsRepository.delete(id: id)
        guard deleted else {
            appendLog("Could not delete WhatsApp Web account.", level: .warning)
            return
        }

        let removedWasSelected = selectedWhatsAppWebAccountId == id
        whatsAppWebSessionStore.removeSession(accountId: id)
        whatsAppWebAccounts.removeAll { $0.id == id }
        if removedWasSelected {
            selectedWhatsAppWebAccountId = whatsAppWebAccounts.first?.id
        }
        appendLog("Deleted WhatsApp Web account.")
    }

    var selectedWhatsAppWebAccount: WhatsAppWebAccount? {
        guard let selectedWhatsAppWebAccountId else {
            return nil
        }

        return whatsAppWebAccounts.first { $0.id == selectedWhatsAppWebAccountId }
    }
}
