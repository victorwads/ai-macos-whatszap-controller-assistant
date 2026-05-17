import Foundation

@MainActor
final class WhatsAppPollingOrchestrator {
    private let memoryStore: WhatsAppMemoryStore
    private let appendLog: (String, LogLevel) -> Void
    private var listSignaturesById: [String: String] = [:]

    init(
        memoryStore: WhatsAppMemoryStore,
        appendLog: @escaping (String, LogLevel) -> Void
    ) {
        self.memoryStore = memoryStore
        self.appendLog = appendLog
    }

    func refresh(provider: WhatsAppIntegrationProvider, messageLimit: Int) async {
        do {
            let conversations = try await provider.parser.listConversations()
            memoryStore.replaceConversations(conversations)
            await refreshChangedChats(
                provider: provider,
                conversations: conversations,
                messageLimit: messageLimit
            )
        } catch {
            appendLog("Polling refresh failed: \(error.localizedDescription)", .error)
        }
    }

    private func refreshChangedChats(
        provider: WhatsAppIntegrationProvider,
        conversations: [ConversationSummary],
        messageLimit: Int
    ) async {
        for conversation in conversations {
            let previous = listSignaturesById[conversation.id]
            let signatureChanged = previous != conversation.listSignature
            if previous == nil || signatureChanged {
                listSignaturesById[conversation.id] = conversation.listSignature
            }

            let isMissingCachedMessages = memoryStore.chatState(for: conversation.id) == nil
            let needsMessages = isMissingCachedMessages || previous == nil || signatureChanged
            guard needsMessages else { continue }

            do {
                try await provider.interactor.openConversation(conversation)
                let read = try await provider.parser.readMessages(limit: messageLimit)
                let chatState = ChatState(
                    chat: conversation,
                    messages: read.messages,
                    composeFocused: read.composeFocused,
                    canSendText: read.canSendText
                )
                memoryStore.upsertChatState(chatState)
                appendLog("Loaded \(read.messages.count) messages for \(conversation.name).", .info)
            } catch {
                appendLog("Failed to load messages for \(conversation.name): \(error.localizedDescription)", .warning)
            }
        }
    }
}

