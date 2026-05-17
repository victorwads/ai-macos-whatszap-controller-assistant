import Foundation

extension AppModel {
    func loadWhatsAppWebAccounts() async {
        let accounts = await whatsAppWebAccountsRepository.list()
        whatsAppWebAccounts = accounts
        whatsAppWebSessionStore.warmSessions(for: accounts)
        restartWhatsAppWebBridgePolling()

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
            restartWhatsAppWebBridgePolling()
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
        whatsAppWebPageSnapshotsByAccountId.removeValue(forKey: id)
        restartWhatsAppWebBridgePolling()
        appendLog("Deleted WhatsApp Web account.")
    }

    var selectedWhatsAppWebAccount: WhatsAppWebAccount? {
        guard let selectedWhatsAppWebAccountId else {
            return nil
        }

        return whatsAppWebAccounts.first { $0.id == selectedWhatsAppWebAccountId }
    }

    var selectedWhatsAppWebPageSnapshot: WhatsAppWebPageSnapshot? {
        guard let selectedWhatsAppWebAccountId else {
            return nil
        }

        return whatsAppWebPageSnapshotsByAccountId[selectedWhatsAppWebAccountId]
    }

    func captureWhatsAppWebSnapshot(for account: WhatsAppWebAccount) async {
        let webView = whatsAppWebSessionStore.webView(for: account)

        do {
            let snapshot = try await whatsAppWebBridge.captureSnapshot(from: webView)
            whatsAppWebPageSnapshotsByAccountId[account.id] = snapshot
        } catch {
            appendLog("WhatsApp Web snapshot failed for '\(account.name)': \(error.localizedDescription)", level: .warning)
        }
    }

    func captureAndSaveWhatsAppWebSnapshot(for account: WhatsAppWebAccount) async {
        let webView = whatsAppWebSessionStore.webView(for: account)

        do {
            let snapshot = try await whatsAppWebBridge.captureSnapshot(from: webView)
            whatsAppWebPageSnapshotsByAccountId[account.id] = snapshot
            _ = whatsAppWebDebugCaptureService.saveSnapshot(accountName: account.name, snapshot: snapshot)
        } catch {
            appendLog("WhatsApp Web snapshot failed for '\(account.name)': \(error.localizedDescription)", level: .warning)
        }
    }

    func restartWhatsAppWebBridgePolling() {
        whatsAppWebBridgePollingTask?.cancel()
        whatsAppWebBridgePollingTask = nil

        guard whatsAppWebSettings.bridgePollingEnabled, !whatsAppWebAccounts.isEmpty else {
            return
        }

        let intervalSeconds = max(1.0, whatsAppWebSettings.bridgePollingIntervalSeconds)
        whatsAppWebBridgePollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let accounts = self.whatsAppWebAccounts
                for account in accounts {
                    if Task.isCancelled { return }
                    await self.captureWhatsAppWebSnapshot(for: account)
                }

                do {
                    try await Task.sleep(for: .seconds(intervalSeconds))
                } catch {
                    return
                }
            }
        }
    }
}
