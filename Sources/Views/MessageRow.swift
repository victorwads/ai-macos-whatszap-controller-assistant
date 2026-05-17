import SwiftUI

struct MessageRow: View {
    let message: Message
    let onMarkAsUnhandled: (() -> Void)?
    let onMarkAsUnhandledAndFollowing: (() -> Void)?
    let onMarkAsHandled: (() -> Void)?
    let onMarkAsHandledAndFollowing: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(message.direction.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(message.kind.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(message.status.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                statusChip

                Spacer()

                if let timestampLabel {
                    Text(timestampLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(message.text ?? message.rawAccessibilityText)
                .font(.body)
                .textSelection(.enabled)

            if shouldShowMarkUnhandledMenu {
                HStack {
                    Spacer()

                    Menu("Desler") {
                        Button("Desler so esta") {
                            onMarkAsUnhandled?()
                        }

                        Button("Desler esta e seguintes") {
                            onMarkAsUnhandledAndFollowing?()
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .help("Recoloca esta mensagem, ou ela e as seguintes, na fila dos waits do assistente.")
                }
            }

            if shouldShowMarkHandledMenu {
                HStack {
                    Spacer()

                    Menu("Mark as read") {
                        Button("Mark this as read") {
                            onMarkAsHandled?()
                        }

                        Button("Mark this and following as read") {
                            onMarkAsHandledAndFollowing?()
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .help("Marks this message, or this message and the following ones, as read by the assistant.")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusChip: some View {
        Text(message.isHandled ? "handled" : "pending")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(message.isHandled ? Color.secondary : Color.orange)
    }

    private var shouldShowMarkUnhandledMenu: Bool {
        message.direction == .incoming && message.isHandled
    }

    private var shouldShowMarkHandledMenu: Bool {
        message.direction == .incoming && !message.isHandled
    }

    private var timestampLabel: String? {
        if let timestamp = message.timestamp {
            return timestamp.formatted(date: .abbreviated, time: .shortened)
        }

        return message.whatsappTimestampText
    }

    private var backgroundColor: Color {
        if message.direction == .incoming && !message.isHandled {
            return .orange.opacity(0.10)
        }

        return Color(nsColor: .controlBackgroundColor)
    }
}

#Preview {
    MessageRow(
        message: Message(
            id: "m-preview",
            chatId: "chat-preview",
            direction: .incoming,
            kind: .text,
            text: "Olá! Isso é um preview.",
            durationSeconds: nil,
            timestamp: Date(),
            status: .delivered,
            rawAccessibilityText: "Olá! Isso é um preview."
        ),
        onMarkAsUnhandled: {},
        onMarkAsUnhandledAndFollowing: {},
        onMarkAsHandled: {},
        onMarkAsHandledAndFollowing: {}
    )
    .padding()
    .frame(width: 420)
}
