import Foundation

struct WhatsAppAccessibilityMap {
    let chatListPath = "0.0.0.2.1.0"
    let messageListPath = "0.0.0.4.1.0"
    // This path can shift between WhatsApp versions; keep it as a fast path only.
    let composePath = "0.0.0.4.1.3"

    func chatList(in root: RawAXNode) -> RawAXNode? {
        if let anchored = root.node(at: chatListPath),
           anchored.nodeDescription?.contains("List of chats") == true {
            return anchored
        }

        return root.firstDescendant { node in
            node.nodeDescription?.contains("List of chats") == true
        }
    }

    func messageList(in root: RawAXNode) -> RawAXNode? {
        if let anchored = root.node(at: messageListPath),
           anchored.nodeDescription?.contains("Messages in chat with") == true {
            return anchored
        }

        return root.firstDescendant { node in
            node.nodeDescription?.contains("Messages in chat with") == true
        }
    }

    func composeField(in root: RawAXNode) -> RawAXNode? {
        if let anchored = root.node(at: composePath),
           anchored.role == "AXTextArea",
           anchored.nodeDescription?.contains("Compose message") == true {
            return anchored
        }

        return root.firstDescendant { node in
            guard node.role == "AXTextArea" else { return false }
            let desc = node.nodeDescription?.normalizedAXText.lowercased() ?? ""
            if desc.contains("compose message") { return true }
            if desc.contains("mensagem") { return true } // Portuguese variants
            if desc.contains("message") { return true }
            return false
        }
    }

    func sendButton(in root: RawAXNode) -> RawAXNode? {
        root.firstDescendant { node in
            let texts = [node.title, node.nodeDescription, node.help, node.stringValue]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")

            return node.role == "AXButton" && (texts.contains("send") || texts.contains("enviar"))
        }
    }
}
