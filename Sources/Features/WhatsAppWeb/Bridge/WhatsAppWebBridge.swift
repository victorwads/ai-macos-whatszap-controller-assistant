import Foundation
import WebKit

enum WhatsAppWebBridgeError: LocalizedError {
    case unexpectedResponse
    case invalidSnapshotPayload
    case elementNotFound(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return "Unexpected JavaScript response from WhatsApp Web."
        case .invalidSnapshotPayload:
            return "Could not decode WhatsApp Web snapshot payload."
        case .elementNotFound(let details):
            return "Could not find the target element in WhatsApp Web. \(details)"
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
        let preview: String?
        let timeText: String?
        let unreadCount: Int?
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
        let json = try await webView.evaluateJavaScriptString(script)

        struct OpenChatResult: Codable {
            let result: String
            let target: String
            let rowCount: Int
            let sampleTitles: [String]
        }

        guard let data = json.data(using: .utf8) else {
            throw WhatsAppWebBridgeError.invalidSnapshotPayload
        }

        let parsed = (try? JSONDecoder().decode(OpenChatResult.self, from: data))
        guard parsed?.result == "ok" else {
            let rowCount = parsed?.rowCount ?? -1
            let sample = (parsed?.sampleTitles ?? []).prefix(12).joined(separator: " | ")
            throw WhatsAppWebBridgeError.elementNotFound("openChatByTitle(target='\(title)') rowCount=\(rowCount) sampleTitles=[\(sample)]")
        }
    }

    func captureDebugDOM(from webView: WKWebView) async throws -> WhatsAppWebDebugDOMSnapshot {
        let json = try await webView.evaluateJavaScriptString(Self.debugDOMScript)
        guard let data = json.data(using: .utf8) else {
            throw WhatsAppWebBridgeError.invalidSnapshotPayload
        }
        do {
            return try JSONDecoder().decode(WhatsAppWebDebugDOMSnapshot.self, from: data)
        } catch {
            throw WhatsAppWebBridgeError.invalidSnapshotPayload
        }
    }

    private static let snapshotScript = """
    (() => {
      const pickText = (value) => typeof value === 'string' ? value.trim() : '';
      const bodyText = pickText(document.body?.innerText || '');
      const hasQrCanvas = document.querySelectorAll('canvas').length > 0;
      const headerTitleNode = document.querySelector('[data-testid="conversation-info-header-chat-title"]') ||
        document.querySelector('[data-testid="conversation-info-header"] [title]') ||
        null;
      const selectedChatTitle =
        pickText(headerTitleNode?.getAttribute('title')) ||
        pickText(headerTitleNode?.textContent || '') ||
        null;
      const composeCandidate =
        document.querySelector('[contenteditable="true"][data-tab]') ||
        document.querySelector('[contenteditable="true"][role="textbox"]');
      const composePlaceholder =
        pickText(composeCandidate?.getAttribute('data-lexical-editor')) ? 'lexical-editor' :
        (pickText(composeCandidate?.getAttribute('aria-label')) || null);
      const unreadBadgeCount = document.querySelectorAll('[aria-label*="unread"], [data-testid*="icon-unread"], [data-testid="icon-unread-count"]').length;
      const chatList = document.querySelector('[data-testid="chat-list"]');
      const chatRowCount = chatList?.querySelectorAll('[data-testid^="list-item-"]').length || 0;
      const bodyTextSample = pickText(document.body?.innerText || '').slice(0, 500);

      const isLoginQr = hasQrCanvas && (bodyText.includes('Scan to log in') || bodyText.includes('Scan the QR code') || bodyText.includes('Scan to log in'));
      const isDownloading = bodyText.includes('mensagens estão sendo baixadas') || bodyText.includes('messages are being downloaded');
      const isChatList = !!document.querySelector('[data-testid="chat-list"]');
      const hasConversationPanel = !!document.querySelector('[data-testid="conversation-panel-wrapper"]');

      let flow = 'unknown';
      if (isLoginQr) flow = 'loginQr';
      else if (isDownloading) flow = 'downloading';
      else if (hasConversationPanel && selectedChatTitle) flow = 'chatSelected';
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
      const main = document.querySelector('#main') || document;

      // Prefer the chat header title; the sidebar's aria-selected row can be stale during transitions.
      const headerTitleCandidate =
        document.querySelector('[data-testid="conversation-info-header-chat-title"]') ||
        document.querySelector('[data-testid="conversation-info-header"] [title]') ||
        main.querySelector('header [title]') ||
        null;

      const sidebarSelected = document.querySelector('[data-testid="chat-list"] [aria-selected="true"]');
      const selectedChatTitle =
        pickText(headerTitleCandidate?.getAttribute('title')) ||
        pickText(headerTitleCandidate?.textContent || '') ||
        pickText(sidebarSelected?.querySelector('[title]')?.getAttribute('title')) ||
        pickText(sidebarSelected?.textContent || '') ||
        null;

      const isLoginQr = hasQrCanvas && (bodyText.includes('Scan to log in') || bodyText.includes('Scan the QR code'));
      const isDownloading = bodyText.includes('mensagens estão sendo baixadas') || bodyText.includes('messages are being downloaded');
      const isChatList = !!document.querySelector('[data-testid="chat-list"]');
      const hasConversationPanel = !!document.querySelector('[data-testid="conversation-panel-wrapper"]');

      let flow = 'unknown';
      if (isLoginQr) flow = 'loginQr';
      else if (isDownloading) flow = 'downloading';
      else if (hasConversationPanel && selectedChatTitle) flow = 'chatSelected';
      else if (isChatList) flow = 'chatList';

      const limit = __LIMIT__;
      // IMPORTANT: message nodes must be scoped to the main conversation pane.
      // Using generic selectors like `div[role="row"]` will accidentally capture the sidebar chat list.
      const panelBody = document.querySelector('[data-testid="conversation-panel-body"]') || main;
      const msgContainers = Array.from(panelBody.querySelectorAll('[data-testid="msg-container"]'));
      const tail = msgContainers.slice(Math.max(0, msgContainers.length - limit));

      const messages = tail.map((container) => {
        const root = container.closest('.message-in, .message-out') || container;
        const selectable = container.querySelector('[data-testid="selectable-text"]');
        const rawText = pickText(selectable?.textContent || container.textContent || '');
        const text = rawText.replace(/\\s+/g, ' ').trim();

        let direction = 'unknown';
        const cls = root?.classList;
        if (cls?.contains('message-in')) direction = 'incoming';
        if (cls?.contains('message-out')) direction = 'outgoing';
        if (direction === 'unknown') {
          if (container.querySelector('[data-testid="tail-in"]')) direction = 'incoming';
          if (container.querySelector('[data-testid="tail-out"]')) direction = 'outgoing';
        }

        const meta =
          root.querySelector('[data-testid="msg-meta"]') ||
          container.querySelector('[data-testid="msg-meta"]') ||
          root.querySelector('span[aria-label][role="img"]') ||
          root.querySelector('span[aria-label]') ||
          null;
        const timestampText =
          pickText(meta?.getAttribute('aria-label')) ||
          pickText(meta?.innerText) ||
          null;

        // Group messages often expose the sender as a clickable span with a title attribute.
        const authorNode =
          root.querySelector('[data-testid="author"]') ||
          container.querySelector('[data-testid="author"]') ||
          null;
        const authorName = pickText(authorNode?.getAttribute('title')) || pickText(authorNode?.textContent || '') || null;

        // Best-effort status from check icons in msg-meta.
        let statusTestId = null;
        const statusNode =
          root.querySelector('[data-testid^="msg-"][data-icon]') ||
          root.querySelector('[data-testid^="msg-"]') ||
          null;
        if (statusNode) {
          const t = statusNode.getAttribute('data-testid') || '';
          // Observed: msg-dblcheck (delivered/read), msg-check (sent)
          statusTestId = t;
        }

        return { direction, authorName, text, timestampText, statusTestId };
      }).filter((m) => m.text.length > 0);

      return JSON.stringify({ flow, selectedChatTitle, messages });
    })();
    """

    private static let chatListScript = """
    (() => {
      const pickText = (value) => typeof value === 'string' ? value.trim() : '';
      const limit = __LIMIT__;
      const chatList = document.querySelector('[data-testid="chat-list"]');
      const pane = chatList || document.querySelector('#pane-side') || document;

      const rows = Array.from(pane.querySelectorAll('[data-testid^="list-item-"], div[role="row"], div[role="listitem"]'));
      const deny = new Set(['WhatsApp', 'Tudo', 'Não lidas', 'Grupos', 'Unread', 'Groups', 'All']);

      const unique = [];
      const seen = new Set();

      const looksLikeTime = (t) => {
        const s = pickText(t);
        if (!s) return false;
        if (/^\\d{1,2}:\\d{2}$/.test(s)) return true;
        if (/^(ontem|yesterday)$/i.test(s)) return true;
        if (/^(hoje|today)$/i.test(s)) return true;
        return false;
      };

      const push = (title, preview, timeText, unreadCount) => {
        const t = pickText(title);
        if (!t) return;
        if (deny.has(t)) return;
        if (seen.has(t)) return;
        seen.add(t);
        unique.push({
          title: t,
          preview: preview ? pickText(preview) : null,
          timeText: timeText ? pickText(timeText) : null,
          unreadCount: typeof unreadCount === 'number' ? unreadCount : null
        });
      };

      for (const row of rows) {
        const titleNode =
          row.querySelector('[data-testid="cell-frame-title"] [title]') ||
          row.querySelector('[title]') ||
          null;
        const titleFromAttr = pickText(titleNode?.getAttribute('title')) || pickText(titleNode?.textContent || '');
        const label = pickText(row.getAttribute('aria-label')) || pickText(row.textContent || '');
        const lines = label.split('\\n').map((l) => pickText(l)).filter((l) => l.length > 0);
        const title = titleFromAttr || lines[0] || '';

        // Best-effort preview and time from line heuristics.
        const timeNode = row.querySelector('[data-testid="cell-frame-primary-detail"]');
        let timeText = pickText(timeNode?.textContent || '') || null;
        if (!timeText) timeText = null;
        for (const l of lines.slice(0, 6)) {
          if (looksLikeTime(l)) { timeText = l; break; }
        }
        const previewNode = row.querySelector('[data-testid="cell-frame-secondary"] [title]') || row.querySelector('[data-testid="cell-frame-secondary"]');
        const preview = pickText(previewNode?.getAttribute('title')) || pickText(previewNode?.textContent || '') || (lines.find((l, idx) => idx > 0 && !looksLikeTime(l)) || null);

        // Best-effort unread badge count.
        const unreadBadge =
          row.querySelector('[data-testid="icon-unread-count"]') ||
          row.querySelector('[aria-label*="unread"]') ||
          null;
        let unreadCount = null;
        if (unreadBadge) {
          const n = parseInt(pickText(unreadBadge.textContent || ''), 10);
          if (!Number.isNaN(n)) unreadCount = n;
          else unreadCount = 1;
        }

        push(title, preview, timeText, unreadCount);
        if (unique.length >= limit) break;
      }

      // Last resort: scan title attrs under pane-side.
      if (unique.length === 0) {
        const titleNodes = Array.from(pane.querySelectorAll('[title]'))
          .map((n) => pickText(n.getAttribute('title')))
          .filter((t) => t.length > 0);
        for (const t of titleNodes) {
          push(t, null, null, null);
          if (unique.length >= limit) break;
        }
      }

      return JSON.stringify(unique.slice(0, limit));
    })();
    """

    private static let openChatScript = """
    (() => {
      const pickText = (value) => typeof value === 'string' ? value.trim() : '';
      const norm = (value) => pickText(value).toLowerCase();
      const target = "__TITLE__";
      const pane = document.querySelector('[data-testid="chat-list"]') || document.querySelector('#pane-side') || document;
      const rows = Array.from(pane.querySelectorAll('[data-testid^="list-item-"], div[role="row"], div[role="listitem"]'));
      const targetKey = norm(target);

      const sampleTitles = [];
      for (const row of rows.slice(0, 20)) {
        const t = row.querySelector('[data-testid="cell-frame-title"] [title]')?.getAttribute('title') ||
          row.querySelector('[title]')?.getAttribute('title') ||
          pickText((row.textContent || '').split('\\n')[0]);
        const v = pickText(t);
        if (v) sampleTitles.push(v);
      }

      const findRow = () => {
        // Prefer matching a [title] descendant.
        for (const row of rows) {
          const t = row.querySelector('[data-testid="cell-frame-title"] [title]')?.getAttribute('title') || row.querySelector('[title]')?.getAttribute('title');
          if (norm(t) === targetKey) return row;
        }
        // Fallback to textContent comparison.
        for (const row of rows) {
          const text = pickText(row.textContent || '');
          const firstLine = norm(text.split('\\n')[0]);
          if (firstLine === targetKey) return row;
        }
        // Fallback: contains match (some titles have extra whitespace/emoji variants).
        for (const row of rows) {
          const text = norm(pickText(row.textContent || ''));
          if (text.includes(targetKey)) return row;
        }
        return null;
      };

      const triggerClick = (node) => {
        if (!node) return false;
        try { node.scrollIntoView({ block: 'center', inline: 'center' }); } catch {}
        try { node.focus?.(); } catch {}
        const eventInit = { bubbles: true, cancelable: true, view: window };
        try { node.dispatchEvent(new MouseEvent('mousedown', eventInit)); } catch {}
        try { node.dispatchEvent(new MouseEvent('mouseup', eventInit)); } catch {}
        try { node.dispatchEvent(new MouseEvent('click', eventInit)); } catch {}
        try { node.click?.(); } catch {}
        return true;
      };

      let clickable = findRow();
      if (!clickable) {
        const candidates = Array.from(pane.querySelectorAll('[title]'));
        const node = candidates.find((n) => norm(n.getAttribute('title')) === targetKey);
        clickable = node?.closest('div[role="listitem"], div[role="row"], button') || node;
      }

      if (!clickable) return JSON.stringify({ result: "not_found", target, rowCount: rows.length, sampleTitles });

      const directTitle = clickable.querySelector('[data-testid="cell-frame-title"] [title]') || clickable.querySelector('[title]') || null;
      const focusTarget =
        clickable.querySelector('[role="gridcell"] div[tabindex="0"][aria-selected]') ||
        clickable.querySelector('[role="gridcell"] [tabindex="0"][aria-selected]') ||
        clickable.querySelector('[role="gridcell"] [tabindex="0"]') ||
        clickable.querySelector('[role="gridcell"]') ||
        clickable;

      triggerClick(directTitle);
      triggerClick(focusTarget);

      return JSON.stringify({
        result: "ok",
        target,
        rowCount: rows.length,
        sampleTitles,
        clickedTitle: pickText(directTitle?.getAttribute('title')) || pickText(directTitle?.textContent || '') || null,
        clickedTag: focusTarget?.tagName || null
      });
    })();
    """

    private static let debugDOMScript = """
    (() => {
      const pickText = (value) => typeof value === 'string' ? value : null;
      const clip = (html) => {
        if (!html) return null;
        // Keep captures reasonably sized; enough for selector iteration.
        const max = 20000;
        return html.length > max ? (html.slice(0, max) + "\\n<!-- truncated -->") : html;
      };

      const chatList = document.querySelector('[data-testid="chat-list"]');
      const panel = document.querySelector('[data-testid="conversation-panel-wrapper"]');
      const headerTitle = document.querySelector('[data-testid="conversation-info-header-chat-title"]');
      const panelBody = document.querySelector('[data-testid="conversation-panel-body"]');

      return JSON.stringify({
        chatListHTML: clip(chatList?.outerHTML || null),
        conversationPanelWrapperHTML: clip(panel?.outerHTML || null),
        conversationHeaderTitleHTML: clip(headerTitle?.outerHTML || null),
        conversationPanelBodyHTML: clip(panelBody?.outerHTML || null),
      });
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
