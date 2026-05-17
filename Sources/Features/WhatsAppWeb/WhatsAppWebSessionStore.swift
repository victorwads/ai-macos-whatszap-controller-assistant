import Foundation
import WebKit

@MainActor
final class WhatsAppWebSessionStore {
    private var webViewsByAccountId: [UUID: WKWebView] = [:]
    private var customUserAgent = WhatsAppWebSettingsModel.defaultCustomUserAgent

    func warmSessions(for accounts: [WhatsAppWebAccount]) {
        for account in accounts {
            _ = webView(for: account)
        }
    }

    func setCustomUserAgent(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedValue = trimmedValue.isEmpty ? WhatsAppWebSettingsModel.defaultCustomUserAgent : trimmedValue
        guard customUserAgent != resolvedValue else {
            return
        }

        customUserAgent = resolvedValue

        for webView in webViewsByAccountId.values {
            webView.customUserAgent = resolvedValue
            if webView.url != nil {
                webView.reload()
            }
        }
    }

    func webView(for account: WhatsAppWebAccount) -> WKWebView {
        if let existing = webViewsByAccountId[account.id] {
            return existing
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: account.profileIdentifier)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.customUserAgent = customUserAgent
        webView.load(URLRequest(url: Self.whatsAppWebURL))

        webViewsByAccountId[account.id] = webView
        return webView
    }

    func removeSession(accountId: UUID) {
        guard let webView = webViewsByAccountId.removeValue(forKey: accountId) else {
            return
        }

        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    private static let whatsAppWebURL = URL(string: "https://web.whatsapp.com")!
}
