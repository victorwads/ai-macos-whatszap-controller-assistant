import AVFoundation
import Speech

@MainActor
final class VoiceAssistant {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?

    func speak(_ text: String, language: String = "pt-BR", voiceIdentifier: String? = nil, rate: Float = AVSpeechUtteranceDefaultSpeechRate) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        utterance.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        synthesizer.speak(utterance)
    }

    func stopSpeaking(immediately: Bool = true) async {
        synthesizer.stopSpeaking(at: immediately ? .immediate : .word)
    }

    func askUser(prompt: String, language: String = "pt-BR", voiceIdentifier: String? = nil, recognitionLocaleIdentifier: String = "pt-BR", timeoutSeconds: Int = 20) async throws -> String {
        await speak(prompt, language: language, voiceIdentifier: voiceIdentifier)
        return try await listen(recognitionLocaleIdentifier: recognitionLocaleIdentifier, timeoutSeconds: timeoutSeconds)
    }

    func listen(recognitionLocaleIdentifier: String = "pt-BR", timeoutSeconds: Int = 20) async throws -> String {
        let timeoutSeconds = max(3, min(timeoutSeconds, 120))

        let speechAuthorized = try await ensureSpeechAuthorization()
        guard speechAuthorized else {
            throw VoiceAssistantError.speechNotAuthorized
        }

        let micAuthorized = await ensureMicrophoneAuthorization()
        guard micAuthorized else {
            throw VoiceAssistantError.microphoneNotAuthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                let locale = Locale(identifier: recognitionLocaleIdentifier)
                guard let recognizer = SFSpeechRecognizer(locale: locale) else {
                    throw VoiceAssistantError.speechRecognizerUnavailable
                }

                let engine = AVAudioEngine()
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true

                let inputNode = engine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    request.append(buffer)
                }

                engine.prepare()
                try engine.start()

                self.audioEngine = engine

                var hasResolved = false

                let timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeoutSeconds))
                    guard !Task.isCancelled else { return }
                    await self?.stopListening()
                    if !hasResolved {
                        hasResolved = true
                        continuation.resume(throwing: VoiceAssistantError.timedOut)
                    }
                }

                self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    if let error {
                        timeoutTask.cancel()
                        Task { await self?.stopListening() }
                        guard !hasResolved else { return }
                        hasResolved = true
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let result else { return }

                    if result.isFinal {
                        timeoutTask.cancel()
                        Task { await self?.stopListening() }
                        guard !hasResolved else { return }
                        hasResolved = true
                        let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: transcript)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func stopListening() {
        recognitionTask?.cancel()
        recognitionTask = nil

        if let audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
    }

    private func ensureSpeechAuthorization() async throws -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    private func ensureMicrophoneAuthorization() async -> Bool {
        let current = AVCaptureDevice.authorizationStatus(for: .audio)
        switch current {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}

enum VoiceAssistantError: LocalizedError {
    case speechNotAuthorized
    case microphoneNotAuthorized
    case speechRecognizerUnavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .speechNotAuthorized:
            return "Speech recognition permission is not authorized."
        case .microphoneNotAuthorized:
            return "Microphone permission is not authorized."
        case .speechRecognizerUnavailable:
            return "Speech recognizer is unavailable for the requested language."
        case .timedOut:
            return "Timed out waiting for speech."
        }
    }
}
