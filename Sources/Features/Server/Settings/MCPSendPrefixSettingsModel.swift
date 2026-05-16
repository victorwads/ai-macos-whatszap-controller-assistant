import Combine
import Foundation

@MainActor
final class MCPSendPrefixSettingsModel: ObservableObject {
    @Published var sendMessagePrefix: String

    private let repository: MCPSendPrefixRepository
    private var cancellables: Set<AnyCancellable> = []

    init(
        loadPersistedValues: Bool = true,
        repository: MCPSendPrefixRepository = .shared
    ) {
        self.repository = repository
        sendMessagePrefix = ""

        guard loadPersistedValues else { return }
        loadStoredValue()
        bindPersistence()
    }

    func applyPrefixIfNeeded(_ text: String) -> String {
        let assistantName = sendMessagePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !assistantName.isEmpty else { return text }
        return "\(assistantName):\n\(text)"
    }

    private func loadStoredValue() {
        sendMessagePrefix = repository.load()
    }

    private func bindPersistence() {
        $sendMessagePrefix
            .dropFirst()
            .sink { [weak self] value in
                self?.repository.save(value)
            }
            .store(in: &cancellables)
    }
}
