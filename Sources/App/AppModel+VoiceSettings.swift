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

    func voiceForIdentifier(_ identifier: String?) -> AVSpeechSynthesisVoice? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return AVSpeechSynthesisVoice(identifier: identifier)
    }

    var availableRecognitionLocales: [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .sorted { $0.identifier < $1.identifier }
    }

    func loadVoiceSettings() {
        speechVoiceIdentifier = UserDefaults.standard.string(forKey: speechVoiceIdentifierDefaultsKey)
        speechLanguage = UserDefaults.standard.string(forKey: speechLanguageDefaultsKey) ?? "pt-BR"
        recognitionLocaleIdentifier = UserDefaults.standard.string(forKey: recognitionLocaleIdentifierDefaultsKey) ?? "pt-BR"

        if let number = UserDefaults.standard.object(forKey: speechRateDefaultsKey) as? NSNumber {
            speechRate = number.floatValue
        }

        bindVoiceSettingsPersistence()
    }

    private func bindVoiceSettingsPersistence() {
        $speechVoiceIdentifier
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                UserDefaults.standard.set(value, forKey: self.speechVoiceIdentifierDefaultsKey)
            }
            .store(in: &cancellables)

        $speechLanguage
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                UserDefaults.standard.set(value, forKey: self.speechLanguageDefaultsKey)

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
                UserDefaults.standard.set(NSNumber(value: value), forKey: self.speechRateDefaultsKey)
            }
            .store(in: &cancellables)

        $recognitionLocaleIdentifier
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                UserDefaults.standard.set(value, forKey: self.recognitionLocaleIdentifierDefaultsKey)
            }
            .store(in: &cancellables)
    }
}
