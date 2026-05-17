import SwiftUI

struct SensitiveDataScreen: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var entries: [SensitiveDataEntry] = []
    @State private var searchQuery = ""
    @State private var searchResults: [SensitiveDataSearchResult] = []
    @State private var audits: [SensitiveDataAuditEntry] = []
    @State private var revealedEntryIDs: Set<UUID> = []
    @State private var errorText: String?
    @State private var isWorking = false

    private var displayedEntries: [SensitiveDataEntry] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entries
        }

        return searchResults.map(\.entry)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Saved")
                        .font(.headline)
                    Spacer()
                }

                TextField("Search sensitive data", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchQuery) { _, _ in
                        Task { await refreshSearch() }
                    }

                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                List(displayedEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.label)
                                    .font(.body.weight(.semibold))
                                Text(entry.key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(entry.kind)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.12))
                                .clipShape(Capsule())

                            Button {
                                Task { await delete(entry) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Delete")

                            Button {
                                toggleReveal(for: entry.id)
                            } label: {
                                Image(systemName: revealedEntryIDs.contains(entry.id) ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(revealedEntryIDs.contains(entry.id) ? "Hide value" : "Show value")
                        }

                        Text(revealedEntryIDs.contains(entry.id) ? entry.value : entry.maskedValue)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            Text("Allowed chats: \(entry.allowedChats.count)")
                            Text("Uses: \(entry.usageHistory.count)")
                            if let lastUsedAt = entry.lastUsedAt {
                                Text("Last used: \(lastUsedAt, style: .date)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Audit Feed")
                        .font(.headline)
                    Spacer()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(audits) { audit in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(audit.action.rawValue.capitalized)
                                        .font(.body.weight(.semibold))
                                    Spacer()
                                    Text(audit.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text(audit.reason)
                                    .font(.callout)

                                HStack(spacing: 8) {
                                    Text("subject: \(audit.subjectId)")
                                    if let key = audit.key {
                                        Text("key: \(key)")
                                    } else if let query = audit.query {
                                        Text("query: \(query)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .frame(width: 380)
        }
        .padding(12)
        .task {
            guard !PreviewSupport.isRunningForPreviews else { return }
            await reload()
        }
        .task {
            guard !PreviewSupport.isRunningForPreviews else { return }
            for await _ in NotificationCenter.default.notifications(named: .sensitiveDataRepositoryDidChange) {
                await reload()
            }
        }
    }

    private func reload() async {
        entries = await appModel.sensitiveDataRepository.peekEntries()
        audits = await appModel.sensitiveDataRepository.listAudits(limit: 50)
        await refreshSearch()
    }

    private func refreshSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchResults = await appModel.sensitiveDataRepository.previewSearch(query: query.isEmpty ? nil : query, limit: 3)
    }

    private func toggleReveal(for entryId: UUID) {
        if revealedEntryIDs.contains(entryId) {
            revealedEntryIDs.remove(entryId)
        } else {
            revealedEntryIDs.insert(entryId)
        }
    }

    private func delete(_ entry: SensitiveDataEntry) async {
        errorText = nil
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await appModel.sensitiveDataRepository.delete(
                id: entry.id,
                subjectId: "sensitive_data_ui",
                reason: "remove entry from Sensitive Data screen"
            )
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    SensitiveDataScreen()
        .environmentObject(AppModel.preview)
        .frame(width: 980, height: 680)
}
