import SwiftUI

struct MemoriesScreen: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var entries: [MemoryEntry] = []
    @State private var searchQuery = ""
    @State private var searchResults: [MemorySearchResult] = []
    @State private var errorText: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved")
                    .font(.headline)
                Spacer()
            }

            TextField("Search memories", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .onChange(of: searchQuery) { _, _ in
                    Task { await refreshSearch() }
                }

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            List(entries) { entry in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.key)
                            .font(.body.weight(.semibold))

                        Text(entry.content)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(entry.updatedAt, style: .date)
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

            if !searchResults.isEmpty {
                Text("Top matches")
                    .font(.headline)

                List(searchResults, id: \.entry.id) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(result.entry.key)
                                .font(.body.weight(.semibold))
                            Spacer()
                            Text(String(format: "%.2f", result.score))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(result.entry.content)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(minHeight: 180)
            }
        }
        .padding(12)
        .task {
            guard !PreviewSupport.isRunningForPreviews else { return }
            await reload()
        }
        .task {
            guard !PreviewSupport.isRunningForPreviews else { return }
            for await _ in NotificationCenter.default.notifications(named: .memoriesRepositoryDidChange) {
                await reload()
            }
        }
    }

    private func reload() async {
        entries = await appModel.memoriesRepository.list()
        await refreshSearch()
    }

    private func refreshSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchResults = await appModel.memoriesRepository.search(query: query.isEmpty ? nil : query, limit: 3)
    }

    private func delete(_ entry: MemoryEntry) async {
        errorText = nil
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await appModel.memoriesRepository.delete(id: entry.id)
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    MemoriesScreen()
        .environmentObject(AppModel.preview)
        .frame(width: 980, height: 680)
}
