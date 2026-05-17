import Combine
import Foundation

@MainActor
final class WhatsAppWebSettingsModel: ObservableObject {
    static let defaultCustomUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5 Safari/605.1.15"

    @Published var customUserAgent: String

    private let repository: WhatsAppWebSettingsRepository
    private var cancellables: Set<AnyCancellable> = []

    init(
        loadPersistedValues: Bool = true,
        repository: WhatsAppWebSettingsRepository = .shared
    ) {
        self.repository = repository
        customUserAgent = Self.defaultCustomUserAgent

        guard loadPersistedValues else { return }
        loadStoredValue()
        bindPersistence()
    }

    var effectiveCustomUserAgent: String {
        let trimmedValue = customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? Self.defaultCustomUserAgent : trimmedValue
    }

    func resetToDefault() {
        customUserAgent = Self.defaultCustomUserAgent
    }

    private func loadStoredValue() {
        customUserAgent = repository.loadCustomUserAgent(defaultValue: Self.defaultCustomUserAgent)
    }

    private func bindPersistence() {
        $customUserAgent
            .dropFirst()
            .sink { [weak self] _ in
                self?.persistStoredValue()
            }
            .store(in: &cancellables)
    }

    private func persistStoredValue() {
        repository.saveCustomUserAgent(effectiveCustomUserAgent)
    }
}
