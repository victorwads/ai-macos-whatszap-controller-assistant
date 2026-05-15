import SwiftUI

struct NicknamesScreen: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var entries: [NicknameEntry] = []
    @State private var selectedChatId: String = ""
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
                Button("Refresh") {
                    Task { await reload() }
                }
                .disabled(isWorking)
            }

            List(entries) { entry in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.nickname)
                            .font(.body.weight(.semibold))

                        Text(entry.chatName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(entry.chatId)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

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
            if selectedChatId.isEmpty {
                selectedChatId = appModel.conversations.first?.id ?? ""
            }
            await reload()
        }
    }

    private var addNicknameSection: some View {
        GroupBox("Add nickname") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Chat", selection: $selectedChatId) {
                    ForEach(appModel.conversations) { conversation in
                        Text(conversation.name)
                            .tag(conversation.id)
                    }
                }

                if !selectedChatId.isEmpty {
                    Text(selectedChatId)
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
        !selectedChatId.isEmpty && !nicknameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reload() async {
        entries = await appModel.nicknamesRepository.list()
    }

    private func save() async {
        errorText = nil
        isWorking = true
        defer { isWorking = false }

        let chatId = selectedChatId.trimmingCharacters(in: .whitespacesAndNewlines)
        let nickname = nicknameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let chatName = appModel.conversations.first(where: { $0.id == chatId })?.name

        do {
            _ = try await appModel.nicknamesRepository.save(chatId: chatId, chatName: chatName, nickname: nickname)
            nicknameText = ""
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

