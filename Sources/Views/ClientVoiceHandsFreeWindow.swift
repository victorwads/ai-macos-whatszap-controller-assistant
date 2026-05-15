import SwiftUI

struct ClientVoiceHandsFreeWindow: View {
    @ObservedObject var appModel: AppModel
    let askId: UUID
    let prompt: String
    let onDone: () -> Void

    @State private var draftResponse = ""
    @State private var isListening = false
    @State private var statusText: String?
    @State private var listenTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Client response pending")
                    .font(.headline)
                Spacer()
                Button {
                    onDone()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(prompt)
                .font(.body)
                .lineLimit(3)

            HStack(spacing: 10) {
                TextField("Speak now… or type the response", text: $draftResponse)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { Task { await submit() } }

                Button {
                    Task { await submit() }
                } label: {
                    Text("Submit")
                }
                .disabled(draftResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 8) {
                if isListening {
                    ProgressView()
                        .controlSize(.small)
                    Text("Listening…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Hands-free is enabled. Waiting for your response.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(14)
        .onAppear { startHandsFreeListening() }
        .onDisappear { listenTask?.cancel() }
    }

    private func startHandsFreeListening() {
        listenTask?.cancel()
        statusText = nil
        isListening = true

        listenTask = Task { @MainActor in
            do {
                let response = try await appModel.voiceAssistant.listenWithAutoSubmit(
                    recognitionLocaleIdentifier: appModel.recognitionLocaleIdentifier,
                    onPartial: { partial in
                        draftResponse = partial
                    }
                )
                draftResponse = response
                isListening = false
                await submit()
            } catch {
                isListening = false
                statusText = error.localizedDescription
            }
        }
    }

    private func submit() async {
        let text = draftResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        do {
            _ = try await appModel.clientVoiceEventsRepository.answerAsk(id: askId, response: text)
            await appModel.refreshPendingClientAskCount()
            onDone()
        } catch {
            statusText = error.localizedDescription
        }
    }
}

