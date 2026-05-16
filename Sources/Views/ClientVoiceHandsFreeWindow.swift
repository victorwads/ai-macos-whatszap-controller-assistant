import SwiftUI

struct ClientVoiceHandsFreeWindow: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var voiceSettings: VoiceSettingsModel
    let askId: UUID
    let prompt: String
    let onDone: () -> Void

    @State private var draftResponse = ""
    @State private var isListening = false
    @State private var statusText: String?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var debounceTask: Task<Void, Never>?
    @State private var sawSpeechStart = false
    @State private var didStartListening = false
    @State private var didResolve = false

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
                    Text("Hands-free is enabled. Waiting for your response.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(14)
        .task(id: appModel.speechSynthesizerSpeaking) {
            guard !PreviewSupport.isRunningForPreviews else { return }
            await handleSpeechStateChange()
        }
        .onDisappear { stopRecognition() }
    }

    private func handleSpeechStateChange() async {
        if appModel.speechSynthesizerSpeaking {
            sawSpeechStart = true
            return
        }

        guard sawSpeechStart else { return }
        guard !didStartListening else { return }
        didStartListening = true
        startHandsFreeListening()
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
                            await finalizeRecognizedText(final, closeWindow: true)
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
            await finalizeRecognizedText(transcript, closeWindow: true)
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

    private func finalizeRecognizedText(_ text: String, closeWindow: Bool) async {
        guard !didResolve else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        didResolve = true
        debounceTask?.cancel()
        debounceTask = nil
        recognitionTask = nil

        appModel.voiceAssistant.stopListening()

        do {
            _ = try await appModel.clientVoiceEventsRepository.answerAsk(id: askId, response: trimmed)
            await appModel.refreshPendingClientAskCount()
            isListening = false
            statusText = nil
            if closeWindow {
                onDone()
            }
        } catch {
            didResolve = false
            isListening = false
            statusText = error.localizedDescription
        }
    }

    private func submitDraft() async {
        await finalizeRecognizedText(draftResponse, closeWindow: true)
    }
}

#Preview {
    let appModel = AppModel.preview
    return ClientVoiceHandsFreeWindow(
        appModel: appModel,
        voiceSettings: appModel.voiceSettings,
        askId: UUID(),
        prompt: "Você pode confirmar o endereço de entrega?",
        onDone: {}
    )
    .frame(width: 560)
    .padding()
}
