import AppKit
import ApplicationServices
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

        app.activate(options: [.activateIgnoringOtherApps])

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

        app.activate(options: [.activateIgnoringOtherApps])

        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = element(at: path, from: root) else {
            throw AccessibilityError.nodeNotFound
        }

        guard performPress(on: element) else {
            throw AccessibilityError.actionFailed(-1)
        }
    }

    func setValue(_ newValue: String, at path: [Int]) throws {
        guard let app = findWhatsAppApplication() else {
            throw AccessibilityError.whatsAppNotRunning
        }

        app.activate(options: [.activateIgnoringOtherApps])

        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = element(at: path, from: root) else {
            throw AccessibilityError.nodeNotFound
        }

        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef)
        guard result == .success else {
            throw AccessibilityError.actionFailed(result.rawValue)
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
