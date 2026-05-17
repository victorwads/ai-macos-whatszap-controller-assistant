import SwiftUI

struct SubjectsScreen: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding private var selectedSubjectId: UUID?

    private enum Filter: String, CaseIterable, Identifiable {
        case active = "Active"
        case all = "All"
        case resolved = "Resolved"
        case canceled = "Canceled"

        var id: String { rawValue }
    }

    @State private var filter: Filter = .active
    @State private var entries: [SubjectEntry] = []
    @State private var detailSubject: SubjectEntry?
    @State private var relatedSensitiveAudits: [SensitiveDataAuditEntry] = []
    @State private var errorText: String?
    @State private var detailErrorText: String?
    @State private var isWorking = false
    @State private var detailLoading = false
    @State private var pendingCancelEntry: SubjectEntry?
    @State private var cancelReason = ""

    init(selectedSubjectId: Binding<UUID?> = .constant(nil)) {
        self._selectedSubjectId = selectedSubjectId
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            subjectsListPane

            if selectedSubjectId != nil {
                Divider()

                SubjectDetailView(
                    subject: detailSubject,
                    relatedSensitiveAudits: relatedSensitiveAudits,
                    isLoading: detailLoading,
                    errorText: detailErrorText,
                    onClose: {
                        selectedSubjectId = nil
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .sheet(item: $pendingCancelEntry) { entry in
            VStack(alignment: .leading, spacing: 16) {
                Text("Cancel Subject")
                    .font(.title3.weight(.semibold))

                Text(entry.title)
                    .font(.headline)

                Text("Reason")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $cancelReason)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )

                HStack {
                    Spacer()

                    Button("Dismiss") {
                        pendingCancelEntry = nil
                        cancelReason = ""
                    }

                    Button("Cancel Subject") {
                        Task { await cancel(entry, reason: cancelReason) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || cancelReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
        .task {
            guard !PreviewSupport.isRunningForPreviews else { return }
            await reload()
        }
        .task {
            guard !PreviewSupport.isRunningForPreviews else { return }
            for await _ in NotificationCenter.default.notifications(named: .subjectsRepositoryDidChange) {
                await reload()
            }
        }
        .task(id: selectedSubjectId) {
            guard !PreviewSupport.isRunningForPreviews else { return }
            await refreshDetail()
        }
    }

    private var subjectsListPane: some View {
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
            }

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            List(filteredEntries, selection: $selectedSubjectId) { entry in
                subjectRow(entry)
                    .contentShape(Rectangle())
            }
        }
        .frame(minWidth: 420, maxWidth: selectedSubjectId == nil ? .infinity : 520)
    }

    private var filteredEntries: [SubjectEntry] {
        switch filter {
        case .active:
            return entries.filter { $0.status == .active }
        case .resolved:
            return entries.filter { $0.status == .resolved }
        case .canceled:
            return entries.filter { $0.status == .canceled }
        case .all:
            return entries
        }
    }

    private func subjectRow(_ entry: SubjectEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.title)
                        .font(.body.weight(.semibold))

                    Text(entry.status.displayName)
                        .font(.caption.monospaced())
                        .foregroundStyle(statusColor(for: entry.status))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor(for: entry.status).opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(entry.summary)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                let initialRequest = entry.initialRequest.trimmingCharacters(in: .whitespacesAndNewlines)
                if !initialRequest.isEmpty {
                    Text("Pedido inicial: \(initialRequest)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                let stopCondition = entry.stopCondition.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stopCondition.isEmpty {
                    Text("Condição de parada: \(stopCondition)")
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

                if let reason = entry.terminalReason, entry.status != .active {
                    Text("Reason: \(reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if !entry.eventLog.isEmpty {
                    Text("Eventos: \(entry.eventLog.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if !entry.nextSteps.isEmpty {
                    Text("Follow-up: \(entry.nextSteps.prefix(2).joined(separator: " • "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !entry.participants.isEmpty {
                    Text("Participants: \(entry.participants.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Text("P\(entry.priority)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    if let chatId = entry.whatsappChatId, !chatId.isEmpty {
                        Text("WA")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .help(chatId)
                    }

                    if let afterMessageId = entry.whatsappAfterMessageId, !afterMessageId.isEmpty {
                        Text("After")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .help(afterMessageId)
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

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.updatedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entry.status == .active {
                Button {
                    pendingCancelEntry = entry
                    cancelReason = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        entries = await appModel.subjectsRepository.listAll()
        await refreshDetail()
    }

    private func refreshDetail() async {
        guard let selectedSubjectId else {
            detailSubject = nil
            relatedSensitiveAudits = []
            detailErrorText = nil
            return
        }

        detailLoading = true
        detailErrorText = nil
        defer { detailLoading = false }

        do {
            detailSubject = try await appModel.subjectsRepository.get(id: selectedSubjectId)
            relatedSensitiveAudits = await appModel.sensitiveDataRepository.listAudits(limit: 100, subjectId: selectedSubjectId.uuidString)
        } catch {
            detailSubject = nil
            relatedSensitiveAudits = []
            detailErrorText = error.localizedDescription
        }
    }

    private func statusColor(for status: SubjectStatus) -> Color {
        switch status {
        case .active:
            return .green
        case .resolved:
            return .blue
        case .canceled:
            return .orange
        }
    }

    private func cancel(_ entry: SubjectEntry, reason: String) async {
        errorText = nil
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await appModel.subjectsRepository.cancel(id: entry.id, reason: reason)
            pendingCancelEntry = nil
            cancelReason = ""
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
