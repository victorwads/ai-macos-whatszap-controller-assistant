import AVFoundation
import Combine
import Foundation
import Speech

extension AppModel {
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

    func loadVoiceSettings() {
        let loaded = VoiceSettingsRepository.shared.load()
        speechVoiceIdentifier = loaded.voiceIdentifier
        speechLanguage = loaded.language
        speechRate = loaded.rate
        recognitionLocaleIdentifier = loaded.recognitionLocale

        bindVoiceSettingsPersistence()
    }

    private func bindVoiceSettingsPersistence() {
        $speechVoiceIdentifier
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                VoiceSettingsRepository.shared.save(
                    voiceIdentifier: value,
                    language: self.speechLanguage,
                    rate: self.speechRate,
                    recognitionLocale: self.recognitionLocaleIdentifier
                )
            }
            .store(in: &cancellables)

        $speechLanguage
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                VoiceSettingsRepository.shared.save(
                    voiceIdentifier: self.speechVoiceIdentifier,
                    language: value,
                    rate: self.speechRate,
                    recognitionLocale: self.recognitionLocaleIdentifier
                )

                if let voice = self.voiceForIdentifier(self.speechVoiceIdentifier),
                   voice.language != value {
                    self.speechVoiceIdentifier = nil
                }
            }
            .store(in: &cancellables)

        $speechRate
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                VoiceSettingsRepository.shared.save(
                    voiceIdentifier: self.speechVoiceIdentifier,
                    language: self.speechLanguage,
                    rate: value,
                    recognitionLocale: self.recognitionLocaleIdentifier
                )
            }
            .store(in: &cancellables)

        $recognitionLocaleIdentifier
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                VoiceSettingsRepository.shared.save(
                    voiceIdentifier: self.speechVoiceIdentifier,
                    language: self.speechLanguage,
                    rate: self.speechRate,
                    recognitionLocale: value
                )
            }
            .store(in: &cancellables)
    }
}
