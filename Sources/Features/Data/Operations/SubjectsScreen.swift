import SwiftUI

struct SubjectsScreen: View {
    @EnvironmentObject private var appModel: AppModel

    private enum Filter: String, CaseIterable, Identifiable {
        case active = "Active"
        case all = "All"
        case resolved = "Resolved"

        var id: String { rawValue }
    }

    @State private var filter: Filter = .active
    @State private var entries: [SubjectEntry] = []
    @State private var errorText: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

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

            List(filteredEntries) { entry in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.body.weight(.semibold))

                        let summary = entry.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !summary.isEmpty {
                            Text(summary)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                        }

                        let initialRequest = entry.initialRequest.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !initialRequest.isEmpty {
                            Text("Pedido inicial: \(initialRequest)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }

                        if let details = entry.details, !details.isEmpty {
                            Text(details)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        if !entry.eventLog.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    "Eventos:\n\(entry.eventLog.map { "• [\($0.timestamp.formatted(date: .omitted, time: .shortened))] \($0.description)" }.joined(separator: "\n"))"
                                )
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(3)
                            }
                        }

                        if !entry.nextSteps.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Follow-up:\n\(entry.nextSteps.prefix(3).map { "• \($0)" }.joined(separator: "\n"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }

                        HStack(spacing: 10) {
                            Text(entry.status.rawValue)
                                .font(.caption.monospaced())
                                .foregroundStyle(entry.status == .active ? .green : .secondary)

                            Text("P\(entry.priority)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)

                            if let chatId = entry.whatsappChatId, !chatId.isEmpty {
                                Text("WA")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .help(chatId)
                            }

                            if let threadId = entry.gmailThreadId, !threadId.isEmpty {
                                Text("Gmail")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .help(threadId)
                            }

                            if let eventId = entry.calendarEventId, !eventId.isEmpty {
                                Text("Cal")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .help(eventId)
                            }
                        }
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

    private var filteredEntries: [SubjectEntry] {
        switch filter {
        case .active:
            return entries.filter { $0.status == .active }
        case .resolved:
            return entries.filter { $0.status == .resolved }
        case .all:
            return entries
        }
    }

    private func reload() async {
        entries = await appModel.subjectsRepository.listAll()
    }

    private func delete(_ entry: SubjectEntry) async {
        errorText = nil
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await appModel.subjectsRepository.delete(id: entry.id)
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    SubjectsScreen()
        .environmentObject(AppModel.preview)
        .frame(width: 980, height: 680)
}
