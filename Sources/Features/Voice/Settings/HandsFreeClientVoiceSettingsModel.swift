import Combine
import Foundation

@MainActor
final class HandsFreeClientVoiceSettingsModel: ObservableObject {
    static let defaultDebounceSeconds = 2.5

    @Published var isEnabled: Bool
    @Published var debounceSeconds: Double

    private let repository: HandsFreeClientVoiceSettingsRepository
    private var cancellables: Set<AnyCancellable> = []

    init(
        loadPersistedValues: Bool = true,
        repository: HandsFreeClientVoiceSettingsRepository = .shared
    ) {
        self.repository = repository
        isEnabled = true
        debounceSeconds = Self.defaultDebounceSeconds

        guard loadPersistedValues else { return }
        loadStoredSettings()
        bindPersistence()
    }

    private func loadStoredSettings() {
        isEnabled = repository.load(defaultValue: true)
        debounceSeconds = repository.loadDebounceSeconds(defaultValue: Self.defaultDebounceSeconds)
    }

    private func bindPersistence() {
        $isEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.repository.save(value)
            }
            .store(in: &cancellables)

        $debounceSeconds
            .dropFirst()
            .sink { [weak self] value in
                self?.repository.save(debounceSeconds: value)
            }
            .store(in: &cancellables)
    }
}
