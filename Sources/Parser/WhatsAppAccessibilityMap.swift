import Foundation

struct WhatsAppAccessibilityMap {
    let chatListPath = "0.0.0.2.1.0"
    let messageListPath = "0.0.0.4.1.0"
    let composePath = "0.0.0.4.1.2"

    func chatList(in root: RawAXNode) -> RawAXNode? {
        root.node(at: chatListPath) ?? root.firstDescendant { node in
            node.nodeDescription?.contains("List of chats") == true
        }
    }

    func messageList(in root: RawAXNode) -> RawAXNode? {
        root.node(at: messageListPath) ?? root.firstDescendant { node in
            node.nodeDescription?.contains("Messages in chat with") == true
        }
    }

    func composeField(in root: RawAXNode) -> RawAXNode? {
        root.node(at: composePath) ?? root.firstDescendant { node in
            node.role == "AXTextArea" && node.nodeDescription?.contains("Compose message") == true
        }
    }
}
