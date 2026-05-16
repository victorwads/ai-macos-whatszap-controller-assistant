import SwiftUI

struct ClientVoicePromptWindow: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var voiceSettings: VoiceSettingsModel
    let onDone: () -> Void

    @State private var draftResponse = ""
    @State private var isListening = false
    @State private var statusText: String?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var debounceTask: Task<Void, Never>?
    @State private var didResolve = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.yellow)
                Text("Waiting for your prompt")
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

            Text("Speak or type what you want the assistant to know right now.")
                .font(.body)
                .lineLimit(2)

            HStack(spacing: 10) {
                TextField("Speak now… or type the prompt", text: $draftResponse)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { Task { await submitDraft() } }

                Button {
                    Task { await submitDraft() }
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
                    Text("Hands-free is on. Listening immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(14)
        .task {
            guard !PreviewSupport.isRunningForPreviews else { return }
            startHandsFreeListening()
        }
        .onDisappear { stopRecognition() }
    }

    private func startHandsFreeListening() {
        recognitionTask?.cancel()
        debounceTask?.cancel()
        statusText = nil
        isListening = true
        didResolve = false

        recognitionTask = Task { @MainActor in
            do {
                try await appModel.voiceAssistant.startListening(
                    recognitionLocaleIdentifier: voiceSettings.recognitionLocaleIdentifier,
                    onPartial: { partial in
                        guard !didResolve else { return }
                        draftResponse = partial
                        scheduleAutoSubmit(with: partial)
                    },
                    onFinal: { final in
                        Task { @MainActor in
                            await finalizeRecognizedText(final)
                        }
                    },
                    onError: { error in
                        Task { @MainActor in
                            handleRecognitionError(error)
                        }
                    }
                )
            } catch {
                recognitionTask = nil
                isListening = false
                statusText = error.localizedDescription
            }
        }
    }

    private func scheduleAutoSubmit(with transcript: String) {
        debounceTask?.cancel()
        let debounceSeconds = max(0.5, appModel.handsFreeClientVoiceSettings.debounceSeconds)

        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(debounceSeconds))
            guard !Task.isCancelled else { return }
            await finalizeRecognizedText(transcript)
        }
    }

    private func handleRecognitionError(_ error: VoiceAssistantError) {
        debounceTask?.cancel()
        recognitionTask = nil
        isListening = false
        statusText = error.localizedDescription
    }

    private func stopRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        Task { @MainActor in
            appModel.voiceAssistant.stopListening()
        }
    }

    private func finalizeRecognizedText(_ text: String) async {
        guard !didResolve else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        didResolve = true
        debounceTask?.cancel()
        debounceTask = nil
        recognitionTask = nil

        appModel.voiceAssistant.stopListening()
        await appModel.submitClientPrompt(trimmed)
        await appModel.refreshPendingClientPromptWaitCount()

        isListening = false
        statusText = nil
        onDone()
    }

    private func submitDraft() async {
        await finalizeRecognizedText(draftResponse)
    }
}

#Preview {
    let appModel = AppModel.preview
    return ClientVoicePromptWindow(
        appModel: appModel,
        voiceSettings: appModel.voiceSettings,
        onDone: {}
    )
    .frame(width: 560)
    .padding()
}
