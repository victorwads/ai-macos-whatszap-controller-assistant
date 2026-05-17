import Foundation

@MainActor
final class WhatsAppWebSettingsRepository {
    static let shared = WhatsAppWebSettingsRepository()

    private let defaults: UserDefaults
    private let userAgentKey = "whatsAppWeb.customUserAgent"
    private let inspectableKey = "whatsAppWeb.isInspectable"
    private let bridgePollingEnabledKey = "whatsAppWeb.bridgePollingEnabled"
    private let bridgePollingIntervalKey = "whatsAppWeb.bridgePollingIntervalSeconds"
    private let pageZoomKey = "whatsAppWeb.pageZoom"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadCustomUserAgent(defaultValue: String) -> String {
        let storedValue = defaults.string(forKey: userAgentKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let storedValue, !storedValue.isEmpty else {
            return defaultValue
        }
        return storedValue
    }

    func saveCustomUserAgent(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmedValue, forKey: userAgentKey)
    }

    func loadInspectable(defaultValue: Bool) -> Bool {
        if defaults.object(forKey: inspectableKey) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: inspectableKey)
    }

    func saveInspectable(_ value: Bool) {
        defaults.set(value, forKey: inspectableKey)
    }

    func loadBridgePollingEnabled(defaultValue: Bool) -> Bool {
        if defaults.object(forKey: bridgePollingEnabledKey) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: bridgePollingEnabledKey)
    }

    func saveBridgePollingEnabled(_ value: Bool) {
        defaults.set(value, forKey: bridgePollingEnabledKey)
    }

    func loadBridgePollingInterval(defaultValue: Double) -> Double {
        if defaults.object(forKey: bridgePollingIntervalKey) == nil {
            return defaultValue
        }
        let value = defaults.double(forKey: bridgePollingIntervalKey)
        return value > 0 ? value : defaultValue
    }

    func saveBridgePollingInterval(_ value: Double) {
        defaults.set(value, forKey: bridgePollingIntervalKey)
    }

    func loadPageZoom(defaultValue: Double) -> Double {
        if defaults.object(forKey: pageZoomKey) == nil {
            return defaultValue
        }
        let value = defaults.double(forKey: pageZoomKey)
        return value > 0 ? value : defaultValue
    }

    func savePageZoom(_ value: Double) {
        defaults.set(value, forKey: pageZoomKey)
    }
}
