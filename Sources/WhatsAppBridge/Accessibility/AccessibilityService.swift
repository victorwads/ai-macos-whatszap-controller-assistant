import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics

final class AccessibilityService {
    func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func currentAppIdentityDescription() -> String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown bundle id"
        let executablePath = Bundle.main.executableURL?.path ?? "unknown executable path"
        let bundlePath = Bundle.main.bundleURL.path

        return """
        Current app identity:
          bundle id: \(bundleIdentifier)
          bundle path: \(bundlePath)
          executable: \(executablePath)
        """
    }

    func findWhatsAppApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            app.bundleIdentifier == "net.whatsapp.WhatsApp"
        }
    }

    func captureWhatsAppSnapshot(maxDepth: Int) throws -> WhatsAppSnapshot {
        guard let app = findWhatsAppApplication() else {
            throw AccessibilityError.whatsAppNotRunning
        }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        let rootNode = captureNode(from: element, path: [], depth: 0, maxDepth: maxDepth)

        return WhatsAppSnapshot(
            bundleIdentifier: app.bundleIdentifier ?? "net.whatsapp.WhatsApp",
            processIdentifier: app.processIdentifier,
            capturedAt: Date(),
            rootNode: rootNode
        )
    }

    func pressNode(at path: [Int]) throws {
        guard let app = findWhatsAppApplication() else {
            throw AccessibilityError.whatsAppNotRunning
        }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        var currentPath = path
        while true {
            guard let element = element(at: currentPath, from: root) else {
                throw AccessibilityError.nodeNotFound
            }

            if performPress(on: element) || clickElementCenter(element) {
                return
            }

            guard !currentPath.isEmpty else {
                break
            }
            currentPath.removeLast()
        }

        throw AccessibilityError.actionFailed(-1)
    }

    func setValue(_ newValue: String, at path: [Int]) throws {
        guard let app = findWhatsAppApplication() else {
            throw AccessibilityError.whatsAppNotRunning
        }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = element(at: path, from: root) else {
            throw AccessibilityError.nodeNotFound
        }

        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef)
        guard result == .success else {
            throw AccessibilityError.actionFailed(result.rawValue)
        }
    }

    func focusNode(at path: [Int]) throws {
        guard let app = findWhatsAppApplication() else {
            throw AccessibilityError.whatsAppNotRunning
        }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = element(at: path, from: root) else {
            throw AccessibilityError.nodeNotFound
        }

        let result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard result == .success else {
            throw AccessibilityError.actionFailed(result.rawValue)
        }
    }

    func pressEnterKey() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw AccessibilityError.actionFailed(-1)
        }

        let enterKeyCode: CGKeyCode = 36
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: enterKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: enterKeyCode, keyDown: false) else {
            throw AccessibilityError.actionFailed(-1)
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    func sendText(_ text: String, to path: [Int]) throws {
        try activateWhatsApp()
        try focusNode(at: path)
        try setValue(text, at: path)
    }

    private func activateWhatsApp() throws {
        guard let app = findWhatsAppApplication() else {
            throw AccessibilityError.whatsAppNotRunning
        }

        if !app.isActive {
            app.activate(options: [.activateAllWindows])
            Thread.sleep(forTimeInterval: 0.15)
        }
    }

    private func captureNode(from element: AXUIElement, path: [Int], depth: Int, maxDepth: Int) -> RawAXNode {
        let children: [RawAXNode]
        if depth < maxDepth {
            let rawChildren: [AXUIElement] = value(element, attribute: kAXChildrenAttribute) ?? []
            children = rawChildren.enumerated().map { index, child in
                captureNode(from: child, path: path + [index], depth: depth + 1, maxDepth: maxDepth)
            }
        } else {
            children = []
        }

        return RawAXNode(
            accessibilityPath: path,
            role: value(element, attribute: kAXRoleAttribute),
            subrole: value(element, attribute: kAXSubroleAttribute),
            title: nonEmpty(value(element, attribute: kAXTitleAttribute)),
            nodeDescription: nonEmpty(value(element, attribute: kAXDescriptionAttribute)),
            help: nonEmpty(value(element, attribute: kAXHelpAttribute)),
            stringValue: stringValue(for: element),
            frame: frame(for: element),
            children: children
        )
    }

    private func element(at path: [Int], from root: AXUIElement) -> AXUIElement? {
        var current = root

        for index in path {
            let children: [AXUIElement] = value(current, attribute: kAXChildrenAttribute) ?? []
            guard children.indices.contains(index) else {
                return nil
            }
            current = children[index]
        }

        return current
    }

    private func performPress(on element: AXUIElement) -> Bool {
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return true
        }

        let children: [AXUIElement] = value(element, attribute: kAXChildrenAttribute) ?? []
        return children.contains { performPress(on: $0) }
    }

    private func clickElementCenter(_ element: AXUIElement) -> Bool {
        guard let frame = frame(for: element) else {
            return false
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        let eventPoint: CGPoint
        if let screenMaxY = NSScreen.screens.map({ $0.frame.maxY }).max() {
            // AX uses a top-left origin in many apps; CGEvent expects bottom-left global coordinates.
            eventPoint = CGPoint(x: center.x, y: screenMaxY - center.y)
        } else {
            eventPoint = center
        }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: eventPoint, mouseButton: .left),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: eventPoint, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: eventPoint, mouseButton: .left)
        else {
            return false
        }

        move.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func value<T>(_ element: AXUIElement, attribute: String) -> T? {
        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        guard result == .success else { return nil }
        return raw as? T
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func stringValue(for element: AXUIElement) -> String? {
        if let text: String = value(element, attribute: kAXValueAttribute) {
            return nonEmpty(text)
        }

        guard let rawValue: CFTypeRef = value(element, attribute: kAXValueAttribute) else {
            return nil
        }

        return nonEmpty(String(describing: rawValue))
    }

    private func frame(for element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = value(element, attribute: kAXPositionAttribute),
              let sizeValue: AXValue = value(element, attribute: kAXSizeAttribute) else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        let hasPosition = AXValueGetValue(positionValue, .cgPoint, &position)
        let hasSize = AXValueGetValue(sizeValue, .cgSize, &size)
        guard hasPosition, hasSize else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }
}

enum AccessibilityError: LocalizedError {
    case whatsAppNotRunning
    case nodeNotFound
    case actionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .whatsAppNotRunning:
            return "WhatsApp is not running."
        case .nodeNotFound:
            return "Accessibility node was not found."
        case .actionFailed(let code):
            return "Accessibility action failed with code \(code)."
        }
    }
}
