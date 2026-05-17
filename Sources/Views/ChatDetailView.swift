import SwiftUI

struct ChatDetailView: View {
    let chatState: ChatState?
    @Binding var messageDraft: String
    let isSendingMessage: Bool
    let isBlocked: Bool
    let accessMode: ConversationAccessMode
    let onToggleBlocked: () -> Void
    let onMarkMessageUnhandled: (Message) -> Void
    let onMarkMessageAndFollowingUnhandled: (Message) -> Void
    let onMarkMessageHandled: (Message) -> Void
    let onMarkMessageAndFollowingHandled: (Message) -> Void
    let onSend: () -> Void

    var body: some View {
        Group {
            if let chatState {
                VStack(alignment: .leading, spacing: 0) {
                    header(for: chatState)
                    Divider()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(chatState.messages.reversed())) { message in
                                MessageRow(
                                    message: message,
                                    onMarkAsUnhandled: {
                                        onMarkMessageUnhandled(message)
                                    },
                                    onMarkAsUnhandledAndFollowing: {
                                        onMarkMessageAndFollowingUnhandled(message)
                                    },
                                    onMarkAsHandled: {
                                        onMarkMessageHandled(message)
                                    },
                                    onMarkAsHandledAndFollowing: {
                                        onMarkMessageAndFollowingHandled(message)
                                    }
                                )
                            }
                        }
                        .padding(14)
                    }
                    Divider()
                    composer
                }
            } else {
                ContentUnavailableView(
                    "No conversation loaded",
                    systemImage: "message",
                    description: Text("Refresh chats or start polling to parse WhatsApp.")
                )
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Write a message", text: $messageDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Button {
                onSend()
            } label: {
                Label(isSendingMessage ? "Sending..." : "Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSendingMessage || messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
    }

    private func header(for chatState: ChatState) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chatState.chat.name)
                    .font(.title3.weight(.semibold))

                Text("\(chatState.messages.count) recent messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if unhandledIncomingCount > 0 {
                    Text("\(unhandledIncomingCount) aguardando assistente")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Label(chatState.canSendText ? "Can send" : "Cannot send", systemImage: chatState.canSendText ? "paperplane" : "paperplane.circle")
                .font(.caption)
                .foregroundStyle(chatState.canSendText ? .green : .secondary)

            Button {
                onToggleBlocked()
            } label: {
                Label(accessActionTitle, systemImage: accessActionSystemImage)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
    }

    private var accessActionTitle: String {
        switch accessMode {
        case .allowAllExceptDeny:
            return isBlocked ? "Remove deny" : "Deny"
        case .denyAllExceptAllow:
            return isBlocked ? "Allow" : "Remove allow"
        }
    }

    private var accessActionSystemImage: String {
        switch accessMode {
        case .allowAllExceptDeny:
            return isBlocked ? "checkmark.shield" : "hand.raised"
        case .denyAllExceptAllow:
            return isBlocked ? "checkmark.circle" : "minus.circle"
        }
    }

    private var unhandledIncomingCount: Int {
        chatState?.messages.filter { $0.direction == .incoming && !$0.isHandled }.count ?? 0
    }
}

#Preview("Loaded") {
    ChatDetailView(
        chatState: AppModel.preview.selectedChatState,
        messageDraft: .constant(""),
        isSendingMessage: false,
        isBlocked: false,
        accessMode: .allowAllExceptDeny,
        onToggleBlocked: {},
        onMarkMessageUnhandled: { _ in },
        onMarkMessageAndFollowingUnhandled: { _ in },
        onMarkMessageHandled: { _ in },
        onMarkMessageAndFollowingHandled: { _ in },
        onSend: {}
    )
    .frame(width: 700, height: 520)
}

#Preview("Empty") {
    ChatDetailView(
        chatState: nil,
        messageDraft: .constant(""),
        isSendingMessage: false,
        isBlocked: false,
        accessMode: .allowAllExceptDeny,
        onToggleBlocked: {},
        onMarkMessageUnhandled: { _ in },
        onMarkMessageAndFollowingUnhandled: { _ in },
        onMarkMessageHandled: { _ in },
        onMarkMessageAndFollowingHandled: { _ in },
        onSend: {}
    )
    .frame(width: 700, height: 520)
}
