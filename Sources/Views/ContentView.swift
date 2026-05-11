import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sidebarHeader("Bridge")
                    Label("WhatsApp", systemImage: appModel.whatsappRunning ? "checkmark.circle.fill" : "xmark.circle")
                    Label("Accessibility", systemImage: appModel.accessibilityTrusted ? "checkmark.circle.fill" : "lock.trianglebadge.exclamationmark")

                    sidebarHeader("Conversations")
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

                    sidebarHeader("Runtime")
                    Text(appModel.runtimeDescription)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                .padding(12)
            }
            .navigationTitle("Assistant MCP")
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                ChatDetailView(
                    chatState: appModel.selectedChatState,
                    messageDraft: $appModel.messageDraft,
                    isSendingMessage: appModel.isSendingMessage,
                    isBlocked: appModel.selectedChatState.map { appModel.isBlocked($0.chat.name) } ?? false,
                    onToggleBlocked: {
                        guard let conversationName = appModel.selectedChatState?.chat.name else {
                            return
                        }

                        appModel.toggleBlockedConversation(conversationName)
                    },
                    onSend: {
                        Task {
                            await appModel.sendMessageToSelectedChat()
                        }
                    }
                )
                    .frame(maxHeight: .infinity)
                Divider()
                LogView(logs: appModel.logs)
                    .frame(minHeight: 180, maxHeight: 260)
            }
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

    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 4)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                appModel.refreshStatus()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Spacer()

            Text(appModel.lastRefreshDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .sheet(isPresented: $showingSettings) {
            SettingsView(appModel: appModel)
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button("Done") {
                    dismiss()
                }
            }

            GroupBox("Polling") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Interval")
                        Spacer()
                        Stepper(value: $appModel.pollingIntervalSeconds, in: 1...30) {
                            Text("\(appModel.pollingIntervalSeconds)s")
                                .monospacedDigit()
                        }
                        .frame(width: 140, alignment: .trailing)
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await appModel.refreshConversations()
                            }
                        } label: {
                            Label("Refresh Chats", systemImage: "list.bullet.rectangle")
                        }

                        Button {
                            if appModel.isPolling {
                                appModel.stopPolling()
                            } else {
                                appModel.startPolling()
                            }
                        } label: {
                            Label(appModel.isPolling ? "Stop Polling" : "Start Polling", systemImage: appModel.isPolling ? "pause.circle" : "play.circle")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Accessibility") {
                HStack(spacing: 10) {
                    Button {
                        appModel.requestAccessibilityPermission()
                    } label: {
                        Label(appModel.waitingForAccessibilityRelaunch ? "Waiting Permission" : "Permission", systemImage: appModel.waitingForAccessibilityRelaunch ? "hourglass" : "lock.open")
                    }
                    .disabled(appModel.waitingForAccessibilityRelaunch)

                    Button {
                        appModel.dumpWhatsAppSnapshot()
                    } label: {
                        Label("Dump WhatsApp", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("MCP Server") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Host")
                        Spacer()
                        TextField("Host", text: $appModel.mcpServerHost)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                    }

                    HStack {
                        Text("Port")
                        Spacer()
                        Stepper(value: $appModel.mcpServerPort, in: 1024...65535) {
                            Text("\(appModel.mcpServerPort)")
                                .monospacedDigit()
                        }
                        .frame(width: 160, alignment: .trailing)
                    }

                    Text("Address: \(appModel.mcpServerAddress)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(appModel.mcpServerStatusDescription)
                        .font(.caption)
                        .foregroundStyle(appModel.mcpServerRunning ? .green : .secondary)

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await appModel.restartMCPServer()
                            }
                        } label: {
                            Label(appModel.mcpServerRunning ? "Restart Server" : "Start Server", systemImage: "bolt.horizontal.circle")
                        }

                        if appModel.mcpServerRunning {
                            Button {
                                Task {
                                    await appModel.stopMCPServer()
                                }
                            } label: {
                                Label("Stop Server", systemImage: "stop.circle")
                            }
                        }
                    }

                    Text("Client snippet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextEditor(text: .constant(appModel.mcpConfigurationSnippet))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        )

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appModel.mcpConfigurationSnippet, forType: .string)
                    } label: {
                        Label("Copy MCP Snippet", systemImage: "doc.on.doc")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Blocked Conversations") {
                if appModel.blockedConversationNames.isEmpty {
                    Text("No blocked conversation titles.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(appModel.blockedConversationNames, id: \.self) { blockedName in
                                HStack {
                                    Text(blockedName)
                                        .lineLimit(1)

                                    Spacer()

                                    Button("Remove") {
                                        appModel.unblockConversation(named: blockedName)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }
}

private struct ConversationRow: View {
    let conversation: ConversationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(conversation.name)
                    .font(.headline)
                    .lineLimit(1)

                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.green))
                }

                Spacer()

                if let lastMessageAtText = conversation.lastMessageAtText {
                    Text(lastMessageAtText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                if conversation.lastMessageDirection == .outgoing {
                    Image(systemName: statusIcon)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }

                Text(conversation.isTyping ? "typing..." : conversation.lastMessagePreview ?? "No preview")
                    .font(.caption)
                    .foregroundStyle(conversation.isTyping ? .green : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch conversation.lastMessageStatus {
        case .read: "checkmark.circle.fill"
        case .delivered: "checkmark.circle"
        case .sent: "checkmark"
        case .unknown: "arrowshape.turn.up.right"
        }
    }

    private var statusColor: Color {
        conversation.lastMessageStatus == .read ? .blue : .secondary
    }
}

private struct ChatDetailView: View {
    let chatState: ChatState?
    @Binding var messageDraft: String
    let isSendingMessage: Bool
    let isBlocked: Bool
    let onToggleBlocked: () -> Void
    let onSend: () -> Void

    var body: some View {
        Group {
            if let chatState {
                VStack(alignment: .leading, spacing: 0) {
                    header(for: chatState)
                    Divider()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(chatState.messages) { message in
                                MessageRow(message: message)
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
            }

            Spacer()

            Label(chatState.canSendText ? "Can send" : "Cannot send", systemImage: chatState.canSendText ? "paperplane" : "paperplane.circle")
                .font(.caption)
                .foregroundStyle(chatState.canSendText ? .green : .secondary)

            Button {
                onToggleBlocked()
            } label: {
                Label(isBlocked ? "Unblock" : "Block", systemImage: isBlocked ? "checkmark.shield" : "hand.raised")
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
    }
}

private struct MessageRow: View {
    let message: Message

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
            }

            Text(message.text ?? message.rawAccessibilityText)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
