import Combine
import Foundation

@MainActor
final class MCPSendPrefixSettingsModel: ObservableObject {
    @Published var sendMessagePrefix: String
    @Published var sendMessageSignature: String

    private let repository: MCPSendPrefixRepository
    private var cancellables: Set<AnyCancellable> = []

    init(
        loadPersistedValues: Bool = true,
        repository: MCPSendPrefixRepository = .shared
    ) {
        self.repository = repository
        sendMessagePrefix = ""
        sendMessageSignature = ""

        guard loadPersistedValues else { return }
        loadStoredValue()
        bindPersistence()
    }

    var assistantName: String {
        sendMessagePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var signature: String {
        sendMessageSignature.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func formattedMessages(for texts: [String]) -> [String] {
        let cleanedTexts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleanedTexts.isEmpty else { return [] }

        if cleanedTexts.count == 1 {
            return [formattedSingleMessage(cleanedTexts[0])]
        }

        var messages: [String] = []
        if !assistantName.isEmpty {
            messages.append("\(assistantName):")
        }
        messages.append(contentsOf: cleanedTexts)
        if !signature.isEmpty {
            messages.append(signature)
        }
        return messages
    }

    private func loadStoredValue() {
        let stored = repository.load()
        sendMessagePrefix = stored.assistantName
        sendMessageSignature = stored.signature
    }

    private func bindPersistence() {
        $sendMessagePrefix
            .dropFirst()
            .sink { [weak self] _ in
                self?.persistStoredValue()
            }
            .store(in: &cancellables)

        $sendMessageSignature
            .dropFirst()
            .sink { [weak self] _ in
                self?.persistStoredValue()
            }
            .store(in: &cancellables)
    }

    private func persistStoredValue() {
        repository.save(assistantName: assistantName, signature: signature)
    }

    private func formattedSingleMessage(_ text: String) -> String {
        let prefix = assistantName
        let suffix = signature

        guard !prefix.isEmpty || !suffix.isEmpty else { return text }

        var parts: [String] = []
        if !prefix.isEmpty {
            parts.append("\(prefix):")
        }
        parts.append(text)
        if !suffix.isEmpty {
            parts.append(suffix)
        }
        return parts.joined(separator: "\n")
    }
}
