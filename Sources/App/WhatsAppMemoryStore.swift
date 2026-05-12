import Foundation

enum WhatsAppMemoryStoreEvent {
    case conversationsUpdated([ConversationSummary])
    case chatStateUpdated(ChatState)
    case selectedConversationChanged(String?)
}

struct WaitForMessageResult {
    let chat: ConversationSummary
    let message: Message
}

@MainActor
final class WhatsAppMemoryStore: ObservableObject {
    static let shared = WhatsAppMemoryStore()

    @Published private(set) var conversations: [ConversationSummary] = []
    @Published private(set) var selectedConversationId: String?
    @Published private(set) var selectedChatState: ChatState?

    private var chatStatesById: [String: ChatState] = [:]
    private var listeners: [UUID: (WhatsAppMemoryStoreEvent) -> Void] = [:]

    private init() {}

    func replaceConversations(_ conversations: [ConversationSummary]) {
        self.conversations = conversations
        let validIDs = Set(conversations.map(\.id))
        chatStatesById = chatStatesById.filter { validIDs.contains($0.key) }

        if let selectedConversationId {
            let latestSelectedConversation = conversations.first { $0.id == selectedConversationId }
            if let latestSelectedConversation {
                if let cachedState = chatStatesById[selectedConversationId] {
                    selectedChatState = ChatState(
                        chat: latestSelectedConversation,
                        messages: cachedState.messages,
                        composeFocused: cachedState.composeFocused,
                        canSendText: cachedState.canSendText
                    )
                } else {
                    selectedChatState = ChatState(
                        chat: latestSelectedConversation,
                        messages: [],
                        composeFocused: false,
                        canSendText: false
                    )
                }
            } else {
                selectedChatState = nil
            }
        }

        emit(.conversationsUpdated(conversations))
    }

    func upsertChatState(_ chatState: ChatState) {
        chatStatesById[chatState.chat.id] = chatState

        if selectedConversationId == chatState.chat.id {
            selectedChatState = chatState
        }

        emit(.chatStateUpdated(chatState))
    }

    func selectConversation(id: String) {
        selectedConversationId = id
        if let conversation = conversations.first(where: { $0.id == id }) {
            selectedChatState = chatStatesById[id] ?? ChatState(
                chat: conversation,
                messages: [],
                composeFocused: false,
                canSendText: false
            )
        } else {
            selectedChatState = chatStatesById[id]
        }
        emit(.selectedConversationChanged(id))
    }

    func clearSelection() {
        selectedConversationId = nil
        selectedChatState = nil
        emit(.selectedConversationChanged(nil))
    }

    func removeConversation(id: String) {
        conversations.removeAll { $0.id == id }
        chatStatesById.removeValue(forKey: id)

        if selectedConversationId == id {
            clearSelection()
        } else {
            emit(.conversationsUpdated(conversations))
        }
    }

    func chatState(for id: String) -> ChatState? {
        chatStatesById[id]
    }

    func conversation(for id: String) -> ConversationSummary? {
        conversations.first(where: { $0.id == id })
    }

    // 12 Hours Timeout
    func waitForNextMessage(chatId: String?, afterMessageId: String?, timeoutSeconds: Int = 43200) async -> WaitForMessageResult? {
        if let immediateMatch = latestMessageResult(chatId: chatId, afterMessageId: afterMessageId) {
            return immediateMatch
        }

        return await withCheckedContinuation { continuation in
            var resolved = false
            var listenerId: UUID?

            func finish(_ result: WaitForMessageResult?) {
                Task { @MainActor in
                    guard !resolved else {
                        return
                    }

                    resolved = true

                    if let listenerId {
                        removeEventListener(listenerId)
                    }

                    continuation.resume(returning: result)
                }
            }

            listenerId = addEventListener { event in
                guard case .chatStateUpdated(let chatState) = event else {
                    return
                }

                guard chatId == nil || chatState.chat.id == chatId else {
                    return
                }

                guard let latestMessage = chatState.messages.last else {
                    return
                }

                if let afterMessageId, latestMessage.id == afterMessageId {
                    return
                }

                finish(WaitForMessageResult(chat: chatState.chat, message: latestMessage))
            }

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                finish(nil)
            }
        }
    }

    @discardableResult
    func addEventListener(_ listener: @escaping (WhatsAppMemoryStoreEvent) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }

    func removeEventListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }

    private func emit(_ event: WhatsAppMemoryStoreEvent) {
        for listener in listeners.values {
            listener(event)
        }
    }

    private func latestMessageResult(chatId: String?, afterMessageId: String?) -> WaitForMessageResult? {
        let candidates: [ChatState]
        if let chatId, let chatState = chatStatesById[chatId] {
            candidates = [chatState]
        } else {
            candidates = Array(chatStatesById.values)
        }

        let latestCandidate = candidates
            .compactMap { chatState -> WaitForMessageResult? in
                guard let latestMessage = chatState.messages.last else {
                    return nil
                }

                if let afterMessageId, latestMessage.id == afterMessageId {
                    return nil
                }

                return WaitForMessageResult(chat: chatState.chat, message: latestMessage)
            }
            .sorted { lhs, rhs in
                switch (lhs.message.timestamp, rhs.message.timestamp) {
                case let (left?, right?):
                    return left > right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.message.id > rhs.message.id
                }
            }
            .first

        return latestCandidate
    }
}
