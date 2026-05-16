import Foundation

struct WhatsAppAccessibilityMap {
    let chatListPath = "0.0.0.2.1.0"
    let messageListPath = "0.0.0.4.1.0"
    // Stable anchor for the current conversation composer container.
    let composeContainerPath = "0.0.0.4.1"

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
        if let anchored = composeContainer(in: root),
           let compose = composeTextArea(in: anchored) {
            return compose
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

    func composeContainer(in root: RawAXNode) -> RawAXNode? {
        if let anchored = root.node(at: composeContainerPath),
           anchored.role == "AXGroup" {
            return anchored
        }

        return root.firstDescendant { node in
            node.role == "AXGroup" && node.accessibilityPath == [0, 0, 0, 4, 1]
        }
    }

    private func composeTextArea(in container: RawAXNode) -> RawAXNode? {
        if let directChild = container.children.first(where: { $0.role == "AXTextArea" }) {
            return directChild
        }

        return container.firstDescendant { node in
            node.role == "AXTextArea"
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
