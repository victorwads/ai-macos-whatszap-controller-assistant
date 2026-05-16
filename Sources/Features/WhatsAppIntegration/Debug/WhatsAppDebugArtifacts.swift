import Foundation

enum WhatsAppDebugArtifacts {
    static func captureYAML(
        name: String,
        focusPath: [Int],
        snapshot: WhatsAppSnapshot,
        screenState: WhatsAppScreenState
    ) -> String {
        var lines: [String] = []
        lines.append("whatsapp_capture:")
        lines.append("  name: \(yamlScalar(name))")
        lines.append("  saved_at: \(yamlScalar(debugCaptureTimestamp(Date())))")
        lines.append("  captured_at: \(yamlScalar(debugCaptureTimestamp(snapshot.capturedAt)))")
        lines.append("  bundle_identifier: \(yamlScalar(snapshot.bundleIdentifier))")
        lines.append("  process_identifier: \(snapshot.processIdentifier)")
        lines.append("  focus_path: \(yamlPath(focusPath))")
        lines.append("  screen_state:")
        lines.append("    selected_chat_name: \(yamlScalar(screenState.selectedChatName))")
        lines.append("    compose_focused: \(yamlBool(screenState.composeFocused))")
        lines.append("    can_send_text: \(yamlBool(screenState.canSendText))")
        lines.append("    send_button_path: \(yamlPath(screenState.sendButtonPath))")

        if screenState.conversations.isEmpty {
            lines.append("    conversations: []")
        } else {
            lines.append("    conversations:")
            for conversation in screenState.conversations {
                lines.append(contentsOf: conversationCaptureLines(conversation, depth: 3))
            }
        }

        if screenState.messages.isEmpty {
            lines.append("    messages: []")
        } else {
            lines.append("    messages:")
            for message in screenState.messages {
                lines.append(contentsOf: messageCaptureLines(message, depth: 3))
            }
        }

        lines.append("  tree:")
        lines.append(contentsOf: snapshot.rootNode.yamlDescription(depth: 2).split(separator: "\n").map(String.init))
        return lines.joined(separator: "\n")
    }

    private static func conversationCaptureLines(_ conversation: ConversationSummary, depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        let childIndent = indent + "  "

        return [
            "\(indent)- id: \(yamlScalar(conversation.id))",
            "\(childIndent)accessibility_path: \(yamlPath(conversation.accessibilityPath))",
            "\(childIndent)name: \(yamlScalar(conversation.name))",
            "\(childIndent)unread_count: \(conversation.unreadCount)",
            "\(childIndent)is_pinned: \(yamlBool(conversation.isPinned))",
            "\(childIndent)is_selected: \(yamlBool(conversation.isSelected))",
            "\(childIndent)last_message_preview: \(yamlScalar(conversation.lastMessagePreview))",
            "\(childIndent)last_message_at_text: \(yamlScalar(conversation.lastMessageAtText))",
            "\(childIndent)last_message_direction: \(yamlScalar(conversation.lastMessageDirection.rawValue))",
            "\(childIndent)last_message_status: \(yamlScalar(conversation.lastMessageStatus.rawValue))",
            "\(childIndent)is_typing: \(yamlBool(conversation.isTyping))"
        ]
    }

    private static func messageCaptureLines(_ message: Message, depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        let childIndent = indent + "  "

        return [
            "\(indent)- id: \(yamlScalar(message.id))",
            "\(childIndent)chat_id: \(yamlScalar(message.chatId))",
            "\(childIndent)direction: \(yamlScalar(message.direction.rawValue))",
            "\(childIndent)kind: \(yamlScalar(message.kind.rawValue))",
            "\(childIndent)text: \(yamlScalar(message.text))",
            "\(childIndent)duration_seconds: \(yamlNumber(message.durationSeconds))",
            "\(childIndent)timestamp: \(yamlScalar(message.timestamp.map(debugCaptureTimestamp)))",
            "\(childIndent)status: \(yamlScalar(message.status.rawValue))",
            "\(childIndent)raw_accessibility_text: \(yamlScalar(message.rawAccessibilityText))"
        ]
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

    private static func yamlNumber(_ value: Double?) -> String {
        guard let value else { return "null" }
        return String(value)
    }

    private static func yamlPath(_ value: [Int]?) -> String {
        guard let value else { return "null" }
        return "[" + value.map(String.init).joined(separator: ", ") + "]"
    }

    private static func debugCaptureTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}
