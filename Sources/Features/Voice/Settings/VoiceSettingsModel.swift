import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class VoiceSettingsModel: ObservableObject {
    @Published var speechVoiceIdentifier: String?
    @Published var speechLanguage: String
    @Published var speechRate: Float
    @Published var recognitionLocaleIdentifier: String
    @Published var experimentalSpeakApiEnabled: Bool

    private let voiceSettingsRepository: VoiceSettingsRepository
    private let experimentalSpeakSettingsRepository: ExperimentalSpeakSettingsRepository
    private var cancellables: Set<AnyCancellable> = []

    init(
        loadPersistedValues: Bool = true,
        voiceSettingsRepository: VoiceSettingsRepository = .shared,
        experimentalSpeakSettingsRepository: ExperimentalSpeakSettingsRepository = .shared
    ) {
        self.voiceSettingsRepository = voiceSettingsRepository
        self.experimentalSpeakSettingsRepository = experimentalSpeakSettingsRepository

        speechVoiceIdentifier = nil
        speechLanguage = "pt-BR"
        speechRate = AVSpeechUtteranceDefaultSpeechRate
        recognitionLocaleIdentifier = "pt-BR"
        experimentalSpeakApiEnabled = true

        guard loadPersistedValues else { return }
        loadStoredSettings()
        bindPersistence()
    }

    var availableSpeechVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted { left, right in
                if left.language != right.language { return left.language < right.language }
                if left.quality != right.quality { return left.quality.rawValue > right.quality.rawValue }
                return left.name < right.name
            }
    }

    func availableSpeechVoices(forLanguage language: String) -> [AVSpeechSynthesisVoice] {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableSpeechVoices }

        let matches = availableSpeechVoices.filter { $0.language == trimmed }
        return matches.isEmpty ? availableSpeechVoices : matches
    }

    var availableSpeechLanguages: [String] {
        let languages = Set(availableSpeechVoices.map(\.language))
        return languages.sorted()
    }

    func voiceForIdentifier(_ identifier: String?) -> AVSpeechSynthesisVoice? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return AVSpeechSynthesisVoice(identifier: identifier)
    }

    var availableRecognitionLocales: [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .sorted { $0.identifier < $1.identifier }
    }

    private func loadStoredSettings() {
        let loadedVoiceSettings = voiceSettingsRepository.load()
        speechVoiceIdentifier = loadedVoiceSettings.voiceIdentifier
        speechLanguage = loadedVoiceSettings.language
        speechRate = loadedVoiceSettings.rate
        recognitionLocaleIdentifier = loadedVoiceSettings.recognitionLocale
        experimentalSpeakApiEnabled = experimentalSpeakSettingsRepository.load(defaultValue: true)
    }

    private func bindPersistence() {
        $speechVoiceIdentifier
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                saveVoiceSettings(voiceIdentifier: value)
            }
            .store(in: &cancellables)

        $speechLanguage
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                saveVoiceSettings(language: value)

                if let voice = voiceForIdentifier(speechVoiceIdentifier),
                   voice.language != value {
                    speechVoiceIdentifier = nil
                }
            }
            .store(in: &cancellables)

        $speechRate
            .dropFirst()
            .sink { [weak self] value in
                self?.saveVoiceSettings(rate: value)
            }
            .store(in: &cancellables)

        $recognitionLocaleIdentifier
            .dropFirst()
            .sink { [weak self] value in
                self?.saveVoiceSettings(recognitionLocale: value)
            }
            .store(in: &cancellables)

        $experimentalSpeakApiEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.experimentalSpeakSettingsRepository.save(value)
            }
            .store(in: &cancellables)
    }

    private func saveVoiceSettings(
        voiceIdentifier: String? = nil,
        language: String? = nil,
        rate: Float? = nil,
        recognitionLocale: String? = nil
    ) {
        voiceSettingsRepository.save(
            voiceIdentifier: voiceIdentifier ?? speechVoiceIdentifier,
            language: language ?? speechLanguage,
            rate: rate ?? speechRate,
            recognitionLocale: recognitionLocale ?? recognitionLocaleIdentifier
        )
    }
}
