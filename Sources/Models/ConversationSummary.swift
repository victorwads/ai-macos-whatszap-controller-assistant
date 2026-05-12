import Foundation

struct ConversationSummary: Identifiable, Equatable {
    let id: String
    let accessibilityPath: [Int]
    let name: String
    let unreadCount: Int
    let isPinned: Bool
    let isSelected: Bool
    let lastMessagePreview: String?
    let lastMessageAtText: String?
    let lastMessageDirection: MessageDirection
    let lastMessageStatus: MessageStatus
    let isTyping: Bool

    var listSignature: String {
        [
            name,
            lastMessagePreview ?? "",
            lastMessageAtText ?? "",
            "\(unreadCount)",
            lastMessageDirection.rawValue,
//            lastMessageStatus.rawValue
        ].joined(separator: "|")
    }
}
