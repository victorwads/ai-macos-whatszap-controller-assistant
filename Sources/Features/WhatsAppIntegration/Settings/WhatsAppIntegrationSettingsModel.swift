import Combine
import Foundation

@MainActor
final class WhatsAppIntegrationSettingsModel: ObservableObject {
    static let defaultMode: WhatsAppIntegrationMode = .web

    @Published var mode: WhatsAppIntegrationMode

    private let repository: WhatsAppIntegrationSettingsRepository
    private var cancellables: Set<AnyCancellable> = []

    init(
        loadPersistedValues: Bool = true,
        repository: WhatsAppIntegrationSettingsRepository = .shared
    ) {
        self.repository = repository
        mode = Self.defaultMode

        guard loadPersistedValues else { return }
        mode = repository.loadMode(defaultValue: Self.defaultMode)
        $mode
            .dropFirst()
            .sink { [weak self] value in
                self?.repository.saveMode(value)
            }
            .store(in: &cancellables)
    }
}

