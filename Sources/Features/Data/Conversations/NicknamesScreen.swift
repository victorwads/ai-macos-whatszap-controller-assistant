import SwiftUI

struct NicknamesScreen: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var entries: [NicknameEntry] = []
    @State private var selectedChatId: String = ""
    @State private var originalNameText: String = ""
    @State private var nicknameText: String = ""
    @State private var errorText: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            addNicknameSection

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Divider()

            HStack {
                Text("Saved")
                    .font(.headline)
                Spacer()
            }

            List(entries) { entry in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.nickname)
                            .font(.body.weight(.semibold))

                        Text(entry.originalName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        if let chatId = entry.chatId, !chatId.isEmpty {
                            Text(chatId)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(entry.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await delete(entry) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .task {
            guard !PreviewSupport.isRunningForPreviews else { return }
            await reload()
        }
        .task {
            guard !PreviewSupport.isRunningForPreviews else { return }
            for await _ in NotificationCenter.default.notifications(named: .nicknamesRepositoryDidChange) {
                await reload()
            }
        }
    }

    private var addNicknameSection: some View {
        GroupBox("Add nickname") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Original name", text: $originalNameText)
                    .textFieldStyle(.roundedBorder)

                Picker("Linked chat", selection: $selectedChatId) {
                    Text("No linked chat").tag("")
                    ForEach(appModel.conversations) { conversation in
                        Text(conversation.name)
                            .tag(conversation.id)
                    }
                }

                if let linkedConversation = appModel.conversations.first(where: { $0.id == selectedChatId }), !selectedChatId.isEmpty {
                    Text(linkedConversation.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    TextField("Nickname", text: $nicknameText)
                        .textFieldStyle(.roundedBorder)

                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isWorking || !canSave)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private var canSave: Bool {
        !nicknameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !originalNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reload() async {
        entries = await appModel.nicknamesRepository.list()
    }

    private func save() async {
        errorText = nil
        isWorking = true
        defer { isWorking = false }

        let chatId = selectedChatId.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalName = originalNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = nicknameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkedConversation = appModel.conversations.first(where: { $0.id == chatId })
        let resolvedOriginalName = originalName.isEmpty ? linkedConversation?.name : originalName

        do {
            _ = try await appModel.nicknamesRepository.save(
                originalName: resolvedOriginalName,
                chatId: chatId.isEmpty ? nil : chatId,
                nickname: nickname
            )
            nicknameText = ""
            originalNameText = ""
            selectedChatId = ""
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete(_ entry: NicknameEntry) async {
        errorText = nil
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await appModel.nicknamesRepository.delete(id: entry.id)
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    NicknamesScreen()
        .environmentObject(AppModel.preview)
        .frame(width: 980, height: 680)
}
