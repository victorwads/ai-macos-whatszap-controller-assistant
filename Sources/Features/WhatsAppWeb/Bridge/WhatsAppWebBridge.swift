import Foundation
import WebKit

enum WhatsAppWebBridgeError: LocalizedError {
    case unexpectedResponse
    case invalidSnapshotPayload
    case elementNotFound

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return "Unexpected JavaScript response from WhatsApp Web."
        case .invalidSnapshotPayload:
            return "Could not decode WhatsApp Web snapshot payload."
        case .elementNotFound:
            return "Could not find the target element in WhatsApp Web."
        }
    }
}

@MainActor
final class WhatsAppWebBridge {
    func captureSnapshot(from webView: WKWebView) async throws -> WhatsAppWebPageSnapshot {
        let script = Self.snapshotScript
        let json = try await webView.evaluateJavaScriptString(script)

        guard let data = json.data(using: .utf8) else {
            throw WhatsAppWebBridgeError.invalidSnapshotPayload
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WhatsAppWebPageSnapshot.self, from: data)
        } catch {
            throw WhatsAppWebBridgeError.invalidSnapshotPayload
        }
    }

    func captureSelectedChat(from webView: WKWebView, limit: Int) async throws -> WhatsAppWebChatCapture {
        let resolvedLimit = max(1, min(limit, 200))
        // Avoid `String(format:)` with large JS blobs; stray `%` sequences can crash by reading invalid varargs.
        let script = Self.chatCaptureScript.replacingOccurrences(of: "__LIMIT__", with: "\(resolvedLimit)")
        let json = try await webView.evaluateJavaScriptString(script)

        guard let data = json.data(using: .utf8) else {
            throw WhatsAppWebBridgeError.invalidSnapshotPayload
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(WhatsAppWebChatCapture.self, from: data)
        } catch {
            throw WhatsAppWebBridgeError.invalidSnapshotPayload
        }
    }

    struct ChatListItem: Codable, Equatable {
        let title: String
    }

    func listChatTitles(from webView: WKWebView, limit: Int) async throws -> [ChatListItem] {
        let resolvedLimit = max(1, min(limit, 200))
        let script = Self.chatListScript.replacingOccurrences(of: "__LIMIT__", with: "\(resolvedLimit)")
        let json = try await webView.evaluateJavaScriptString(script)

        guard let data = json.data(using: .utf8) else {
            throw WhatsAppWebBridgeError.invalidSnapshotPayload
        }

        do {
            return try JSONDecoder().decode([ChatListItem].self, from: data)
        } catch {
            throw WhatsAppWebBridgeError.invalidSnapshotPayload
        }
    }

    func openChatByTitle(from webView: WKWebView, title: String) async throws {
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = Self.openChatScript.replacingOccurrences(of: "__TITLE__", with: escapedTitle)
        let result = try await webView.evaluateJavaScriptString(script)
        guard result == "ok" else {
            throw WhatsAppWebBridgeError.elementNotFound
        }
    }

    private static let snapshotScript = """
    (() => {
      const pickText = (value) => typeof value === 'string' ? value.trim() : '';
      const bodyText = pickText(document.body?.innerText || '');
      const hasQrCanvas = document.querySelectorAll('canvas').length > 0;
      const selectedChatCandidate = document.querySelector('[aria-selected="true"]');
      const selectedChatTitle =
        pickText(selectedChatCandidate?.getAttribute('title')) ||
        pickText(selectedChatCandidate?.querySelector('[title]')?.getAttribute('title')) ||
        null;
      const composeCandidate =
        document.querySelector('[contenteditable="true"][data-tab]') ||
        document.querySelector('[contenteditable="true"][role="textbox"]');
      const composePlaceholder =
        pickText(composeCandidate?.getAttribute('data-lexical-editor')) ? 'lexical-editor' :
        (pickText(composeCandidate?.getAttribute('aria-label')) || null);
      const unreadBadgeCount = document.querySelectorAll('[aria-label*="unread"], [data-testid*="icon-unread"], [data-testid="icon-unread-count"]').length;
      const chatRowCount = document.querySelectorAll('[role="listitem"]').length;
      const bodyTextSample = pickText(document.body?.innerText || '').slice(0, 500);

      const isLoginQr = hasQrCanvas && (bodyText.includes('Scan to log in') || bodyText.includes('Scan the QR code') || bodyText.includes('Scan to log in'));
      const isDownloading = bodyText.includes('mensagens estão sendo baixadas') || bodyText.includes('messages are being downloaded');
      const isChatList = bodyText.includes('Não lidas') || bodyText.includes('Unread') || bodyText.includes('Tudo');

      let flow = 'unknown';
      if (isLoginQr) flow = 'loginQr';
      else if (isDownloading) flow = 'downloading';
      else if (selectedChatTitle) flow = 'chatSelected';
      else if (isChatList) flow = 'chatList';

      const payload = {
        url: window.location.href,
        title: document.title,
        documentReadyState: document.readyState,
        isLoggedIn: !isLoginQr,
        hasQrCanvas,
        chatRowCount,
        unreadBadgeCount,
        selectedChatTitle,
        composePlaceholder,
        bodyTextSample,
        flow,
        capturedAt: new Date().toISOString()
      };
      return JSON.stringify(payload);
    })();
    """

    private static let chatCaptureScript = """
    (() => {
      const pickText = (value) => typeof value === 'string' ? value.trim() : '';
      const bodyText = pickText(document.body?.innerText || '');
      const hasQrCanvas = document.querySelectorAll('canvas').length > 0;
      const selectedChatCandidate = document.querySelector('[aria-selected="true"]');
      const selectedChatTitle =
        pickText(selectedChatCandidate?.getAttribute('title')) ||
        pickText(selectedChatCandidate?.querySelector('[title]')?.getAttribute('title')) ||
        null;

      const isLoginQr = hasQrCanvas && (bodyText.includes('Scan to log in') || bodyText.includes('Scan the QR code'));
      const isDownloading = bodyText.includes('mensagens estão sendo baixadas') || bodyText.includes('messages are being downloaded');
      const isChatList = bodyText.includes('Não lidas') || bodyText.includes('Unread') || bodyText.includes('Tudo');

      let flow = 'unknown';
      if (isLoginQr) flow = 'loginQr';
      else if (isDownloading) flow = 'downloading';
      else if (selectedChatTitle) flow = 'chatSelected';
      else if (isChatList) flow = 'chatList';

      const limit = __LIMIT__;
      let nodes = Array.from(document.querySelectorAll('[data-testid="msg-container"]'));
      if (nodes.length === 0) nodes = Array.from(document.querySelectorAll('div.message-in, div.message-out'));
      if (nodes.length === 0) nodes = Array.from(document.querySelectorAll('div[role="row"]'));

      const tail = nodes.slice(Math.max(0, nodes.length - limit));
      const messages = tail.map((node) => {
        const rawText = pickText(node?.innerText || '');
        const text = rawText.replace(/\\s+/g, ' ').trim();
        let direction = 'unknown';
        const cls = node?.classList;
        if (cls?.contains('message-in')) direction = 'incoming';
        if (cls?.contains('message-out')) direction = 'outgoing';
        if (direction === 'unknown') {
          if (node.querySelector('[data-testid="tail-in"]')) direction = 'incoming';
          if (node.querySelector('[data-testid="tail-out"]')) direction = 'outgoing';
        }

        const meta =
          node.querySelector('[data-testid*="msg-meta"]') ||
          node.querySelector('span[aria-label]') ||
          null;
        const timestampText = pickText(meta?.getAttribute('aria-label')) || pickText(meta?.innerText) || null;

        const authorCandidate =
          node.querySelector('span[dir=\"auto\"][title]') ||
          node.querySelector('span[role=\"button\"][tabindex=\"-1\"]') ||
          null;
        const authorName = pickText(authorCandidate?.getAttribute('title')) || null;

        return { direction, authorName, text, timestampText };
      }).filter((m) => m.text.length > 0);

      return JSON.stringify({ flow, selectedChatTitle, messages });
    })();
    """

    private static let chatListScript = """
    (() => {
      const pickText = (value) => typeof value === 'string' ? value.trim() : '';
      const limit = __LIMIT__;
      // Best-effort: sidebar conversation rows often expose a `title` attribute somewhere.
      const titleNodes = Array.from(document.querySelectorAll('[title]'))
        .map((n) => pickText(n.getAttribute('title')))
        .filter((t) => t.length > 0);

      // Deduplicate and keep only plausible chat names (avoid common UI titles).
      const deny = new Set(['WhatsApp', 'Tudo', 'Não lidas', 'Grupos', 'Unread', 'Groups', 'All']);
      const unique = [];
      const seen = new Set();
      for (const t of titleNodes) {
        if (deny.has(t)) continue;
        if (seen.has(t)) continue;
        seen.add(t);
        unique.push({ title: t });
        if (unique.length >= limit) break;
      }
      return JSON.stringify(unique);
    })();
    """

    private static let openChatScript = """
    (() => {
      const pickText = (value) => typeof value === 'string' ? value.trim() : '';
      const target = "__TITLE__";
      const candidates = Array.from(document.querySelectorAll('[title]'));
      const node = candidates.find((n) => pickText(n.getAttribute('title')) === target);
      if (!node) return "not_found";
      const clickable = node.closest('div[role=\"listitem\"], div[role=\"row\"], button') || node;
      clickable.scrollIntoView({ block: 'center' });
      clickable.click();
      return "ok";
    })();
    """
}

@MainActor
private extension WKWebView {
    func evaluateJavaScriptString(_ javaScript: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(javaScript) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let stringResult = result as? String {
                    continuation.resume(returning: stringResult)
                } else {
                    continuation.resume(throwing: WhatsAppWebBridgeError.unexpectedResponse)
                }
            }
        }
    }
}
