import SwiftUI

struct ConversationsScreen: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showingClearHistoryConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Conversations")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Button("Clear history", role: .destructive) {
                            showingClearHistoryConfirmation = true
                        }
                        .controlSize(.small)
                        .help("Clears all saved WhatsApp data for the integration (keeps allow/deny lists).")

                        Text("\(appModel.conversations.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .confirmationDialog(
                        "Clear all WhatsApp data?",
                        isPresented: $showingClearHistoryConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear", role: .destructive) {
                            appModel.resetWhatsAppIntegrationState()
                        }
                    }

                    ForEach(appModel.conversations) { conversation in
                        Button {
                            open(conversation)
                        } label: {
                            ConversationRow(conversation: conversation)
                                .contentShape(Rectangle())
                                .padding(.horizontal, 4)
                                .background(selectionBackground(for: conversation))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    ignoredConversationsSection
                }
                .padding(12)
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)

            Divider()

            ChatDetailView(
                chatState: appModel.selectedChatState,
                messageDraft: $appModel.messageDraft,
                isSendingMessage: appModel.isSendingMessage,
                isBlocked: appModel.selectedChatState.map { appModel.isBlocked($0.chat.name) } ?? false,
                accessMode: appModel.conversationAccessMode,
                onToggleBlocked: {
                    guard let conversationName = appModel.selectedChatState?.chat.name else {
                        return
                    }

                    appModel.toggleConversationAccess(conversationName)
                },
                onMarkMessageUnhandled: { message in
                    appModel.markMessageAsUnhandled(message)
                },
                onMarkMessageAndFollowingUnhandled: { message in
                    appModel.markMessageAndFollowingAsUnhandled(message)
                },
                onMarkMessageHandled: { message in
                    appModel.markMessageAsHandled(message)
                },
                onMarkMessageAndFollowingHandled: { message in
                    appModel.markMessageAndFollowingAsHandled(message)
                },
                onSend: {
                    Task {
                        await sendSelectedChatMessage()
                    }
                }
            )
        }
    }

    @MainActor
    private func sendSelectedChatMessage() async {
        let trimmedMessage = appModel.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            appModel.appendLog("Cannot send an empty message.", level: .warning)
            return
        }

        guard let selectedChatState = appModel.selectedChatState else {
            appModel.appendLog("No selected conversation available to send a message.", level: .warning)
            return
        }

        appModel.isSendingMessage = true
        defer { appModel.isSendingMessage = false }

        do {
            try await appModel.whatsappMessageSendCoordinator.sendMessageViaScheduler(
                trimmedMessage,
                to: selectedChatState.chat.id
            )
            appModel.messageDraft = ""
        } catch {
            appModel.appendLog("Failed to send message: \(error.localizedDescription)", level: .error)
        }
    }

    private func open(_ conversation: ConversationSummary) {
        guard appModel.selectedConversationId != conversation.id else {
            return
        }

        appModel.openConversation(conversation)
    }

    @ViewBuilder
    private func selectionBackground(for conversation: ConversationSummary) -> some View {
        if appModel.selectedConversationId == conversation.id {
            Color.accentColor.opacity(0.22)
        } else {
            Color.clear
        }
    }

    private var ignoredConversationsSection: some View {
        GroupBox(appModel.conversationAccessMode == .allowAllExceptDeny ? "Deny list" : "Allow list") {
            let names = appModel.conversationAccessMode == .allowAllExceptDeny ? appModel.denyConversationNames : appModel.allowConversationNames
            if names.isEmpty {
                Text(appModel.conversationAccessMode == .allowAllExceptDeny ? "No denied conversations." : "No allowed conversations.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(names, id: \.self) { ignoredName in
                        HStack {
                            Text(ignoredName)
                                .lineLimit(1)

                            Spacer()

                            Button("Remove") {
                                if appModel.conversationAccessMode == .allowAllExceptDeny {
                                    appModel.removeFromDenyList(ignoredName)
                                } else {
                                    appModel.removeFromAllowList(ignoredName)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    ConversationsScreen()
        .environmentObject(AppModel.preview)
        .frame(width: 980, height: 680)
}
