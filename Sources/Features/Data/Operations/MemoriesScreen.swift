import SwiftUI

struct MemoriesScreen: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var entries: [MemoryEntry] = []
    @State private var errorText: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task { await reload() }
                }
                .disabled(isWorking)
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

                        if !entry.tags.isEmpty {
                            Text(entry.tags.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

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
        }
        .padding(12)
        .task {
            guard !PreviewSupport.isRunningForPreviews else { return }
            await reload()
        }
    }

    private func reload() async {
        entries = await appModel.memoriesRepository.list()
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
