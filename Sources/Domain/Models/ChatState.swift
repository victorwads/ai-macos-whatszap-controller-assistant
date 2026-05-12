import Foundation

struct ChatState: Equatable {
    let chat: ConversationSummary
    let messages: [Message]
    let composeFocused: Bool
    let canSendText: Bool
}
