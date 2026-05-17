import Foundation

enum WhatsAppWebDebugArtifacts {
    static func captureYAML(
        accountName: String,
        snapshot: WhatsAppWebPageSnapshot
    ) -> String {
        var lines: [String] = []
        lines.append("whatsapp_web_capture:")
        lines.append("  account_name: \(yamlScalar(accountName))")
        lines.append("  saved_at: \(yamlScalar(debugCaptureTimestamp(Date())))")
        lines.append("  captured_at: \(yamlScalar(debugCaptureTimestamp(snapshot.capturedAt)))")
        lines.append("  url: \(yamlScalar(snapshot.url))")
        lines.append("  title: \(yamlScalar(snapshot.title))")
        lines.append("  document_ready_state: \(yamlScalar(snapshot.documentReadyState))")
        lines.append("  is_logged_in: \(yamlBool(snapshot.isLoggedIn))")
        lines.append("  has_qr_canvas: \(yamlBool(snapshot.hasQrCanvas))")
        lines.append("  chat_row_count: \(snapshot.chatRowCount)")
        lines.append("  unread_badge_count: \(snapshot.unreadBadgeCount)")
        lines.append("  selected_chat_title: \(yamlScalar(snapshot.selectedChatTitle))")
        lines.append("  compose_placeholder: \(yamlScalar(snapshot.composePlaceholder))")
        lines.append("  body_text_sample: \(yamlScalar(snapshot.bodyTextSample))")
        return lines.joined(separator: "\n")
    }

    private static func yamlScalar(_ value: String?) -> String {
        guard let value else { return "null" }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func yamlBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private static func debugCaptureTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}
