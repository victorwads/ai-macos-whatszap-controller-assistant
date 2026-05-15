import AVFoundation
import Foundation

@MainActor
final class VoiceSettingsRepository {
    static let shared = VoiceSettingsRepository()

    private let defaults: UserDefaults

    private let speechVoiceIdentifierDefaultsKey = "speechVoiceIdentifier"
    private let speechLanguageDefaultsKey = "speechLanguage"
    private let speechRateDefaultsKey = "speechRate"
    private let recognitionLocaleIdentifierDefaultsKey = "recognitionLocaleIdentifier"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> (voiceIdentifier: String?, language: String, rate: Float, recognitionLocale: String) {
        let voiceIdentifier = defaults.string(forKey: speechVoiceIdentifierDefaultsKey)
        let language = defaults.string(forKey: speechLanguageDefaultsKey) ?? "pt-BR"
        let recognitionLocale = defaults.string(forKey: recognitionLocaleIdentifierDefaultsKey) ?? "pt-BR"
        let rate: Float = {
            if let number = defaults.object(forKey: speechRateDefaultsKey) as? NSNumber {
                return number.floatValue
            }
            return AVSpeechUtteranceDefaultSpeechRate
        }()

        return (voiceIdentifier: voiceIdentifier, language: language, rate: rate, recognitionLocale: recognitionLocale)
    }

    func save(voiceIdentifier: String?, language: String, rate: Float, recognitionLocale: String) {
        defaults.set(voiceIdentifier, forKey: speechVoiceIdentifierDefaultsKey)
        defaults.set(language, forKey: speechLanguageDefaultsKey)
        defaults.set(NSNumber(value: rate), forKey: speechRateDefaultsKey)
        defaults.set(recognitionLocale, forKey: recognitionLocaleIdentifierDefaultsKey)
    }
}
