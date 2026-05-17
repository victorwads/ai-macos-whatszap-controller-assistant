import Foundation

struct WhatsAppWebChatCapture: Codable, Equatable {
    struct CapturedMessage: Codable, Equatable {
        let direction: MessageDirection
        let authorName: String?
        let text: String
        let timestampText: String?
        /// Raw WA Web status identifier (best-effort), e.g. "msg-check" / "msg-dblcheck".
        let statusTestId: String?
    }

    let flow: WhatsAppWebFlow
    let selectedChatTitle: String?
    let messages: [CapturedMessage]
}
