import Foundation

enum WhatsAppMemoryStoreEvent {
    case conversationsUpdated([ConversationSummary])
    case chatStateUpdated(ChatState)
    case selectedConversationChanged(String?)
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

    func chatState(for id: String) -> ChatState? {
        chatStatesById[id]
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
}
