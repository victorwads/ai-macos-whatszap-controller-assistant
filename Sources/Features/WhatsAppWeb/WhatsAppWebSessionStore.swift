import Foundation
import WebKit

@MainActor
final class WhatsAppWebSessionStore {
    private var webViewsByAccountId: [UUID: WKWebView] = [:]
    private var customUserAgent = WhatsAppWebSettingsModel.defaultCustomUserAgent
    private var isInspectable = WhatsAppWebSettingsModel.defaultInspectable
    private var pageZoom = WhatsAppWebSettingsModel.defaultPageZoom

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

    func setInspectable(_ value: Bool) {
        guard isInspectable != value else {
            return
        }

        isInspectable = value

        for webView in webViewsByAccountId.values {
            if #available(macOS 13.3, *) {
                webView.isInspectable = value
            }
        }
    }

    func setPageZoom(_ value: Double) {
        let resolvedValue = min(max(value, 0.25), 2.0)
        guard pageZoom != resolvedValue else {
            return
        }

        pageZoom = resolvedValue

        for webView in webViewsByAccountId.values {
            webView.pageZoom = resolvedValue
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
        webView.pageZoom = pageZoom
        if #available(macOS 13.3, *) {
            webView.isInspectable = isInspectable
        }
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
