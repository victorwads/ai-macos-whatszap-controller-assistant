import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics

final class AccessibilityService {
    private let inputLock = InputLockService()

    /// Best-effort: bring WhatsApp to the foreground so subsequent CGEvent key injections
    /// are delivered to WhatsApp (not whatever app the user is currently typing in).
    func ensureWhatsAppActive() throws {
        try activateWhatsApp()
    }

    func lockUserInputForSend(seconds: Double) {
        inputLock.lockFor(seconds: seconds)
    }

    func unlockUserInputAfterSend() {
        inputLock.unlock()
    }

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

    /// Tries to press a node using AXPress only (no coordinate clicking fallback).
    /// This is safer for text areas, where a coordinate click can hit an unrelated element.
    func pressNodeAXOnly(at path: [Int]) throws {
        guard let app = findWhatsAppApplication() else {
            throw AccessibilityError.whatsAppNotRunning
        }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = element(at: path, from: root) else {
            throw AccessibilityError.nodeNotFound
        }

        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw AccessibilityError.actionFailed(-1)
        }
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

    func readValue(at path: [Int]) throws -> String? {
        guard let app = findWhatsAppApplication() else {
            throw AccessibilityError.whatsAppNotRunning
        }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = element(at: path, from: root) else {
            throw AccessibilityError.nodeNotFound
        }

        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &raw)
        guard result == .success else {
            throw AccessibilityError.actionFailed(result.rawValue)
        }

        if let text = raw as? String {
            return text
        }
        return raw.map { String(describing: $0) }
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
        try activateWhatsApp()
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw AccessibilityError.actionFailed(-1)
        }

        let enterKeyCode: CGKeyCode = 36
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: enterKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: enterKeyCode, keyDown: false) else {
            throw AccessibilityError.actionFailed(-1)
        }

        tagAsSyntheticForInputLock(keyDown)
        tagAsSyntheticForInputLock(keyUp)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    func sendText(_ text: String, to path: [Int]) throws {
        try activateWhatsApp()
        // Make sure the caret is really in the compose field. AXFocused alone isn't always enough.
        try? pressNodeAXOnly(at: path)
        try focusNode(at: path)
        Thread.sleep(forTimeInterval: 0.05)
        // Clear via AXValue to avoid global Cmd+A hitting the wrong app if focus is stolen.
        // (We still use real input events for the actual text to trigger WhatsApp's change pipeline.)
        try? setValue("", at: path)
        Thread.sleep(forTimeInterval: 0.02)

        do {
            try typeTextViaUnicodeEvents(text)
        } catch {
            // Fallback: paste via clipboard (Cmd+V). This also tends to trigger input events.
            try pasteTextViaClipboard(text)
        }
    }

    private func activateWhatsApp() throws {
        guard let app = findWhatsAppApplication() else {
            throw AccessibilityError.whatsAppNotRunning
        }

        guard !app.isActive else { return }

        // NSRunningApplication activation is more reliable from the main thread.
        let activateBlock = {
            _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            app.unhide()
        }
        if Thread.isMainThread {
            activateBlock()
        } else {
            DispatchQueue.main.sync(execute: activateBlock)
        }

        if waitForActive(app, timeoutSeconds: 1.2) {
            return
        }

        // Fallback: AppleScript activation can succeed in situations where NSRunningApplication.activate
        // does not (Spaces/Focus/other foreground constraints).
        let script = NSAppleScript(source: "tell application \"WhatsApp\" to activate")
        var error: NSDictionary?
        _ = script?.executeAndReturnError(&error)
        if waitForActive(app, timeoutSeconds: 1.2) {
            return
        }

        throw AccessibilityError.actionFailed(-2)
    }

    private func waitForActive(_ app: NSRunningApplication, timeoutSeconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !app.isActive, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return app.isActive
    }

    private func pasteTextViaClipboard(_ text: String) throws {
        try activateWhatsApp()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Thread.sleep(forTimeInterval: 0.02)

        // Cmd+V
        try pressKey(keyCode: 9, flags: .maskCommand) // 'V'
        Thread.sleep(forTimeInterval: 0.05)
    }

    private func typeTextViaUnicodeEvents(_ text: String) throws {
        try activateWhatsApp()
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw AccessibilityError.actionFailed(-1)
        }

        // Send as small unicode chunks to behave like "real typing" and trigger input events.
        // (CGEvent keyboard events have a max unicode payload; keep it modest.)
        let scalars = Array(text.unicodeScalars)
        var idx = 0
        while idx < scalars.count {
            let end = min(idx + 20, scalars.count)
            let chunk = String(String.UnicodeScalarView(scalars[idx..<end]))
            idx = end

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw AccessibilityError.actionFailed(-1)
            }

            tagAsSyntheticForInputLock(keyDown)
            tagAsSyntheticForInputLock(keyUp)

            keyDown.keyboardSetUnicodeString(stringLength: chunk.utf16.count, unicodeString: Array(chunk.utf16))
            keyUp.keyboardSetUnicodeString(stringLength: chunk.utf16.count, unicodeString: Array(chunk.utf16))

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private func pressKey(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        try activateWhatsApp()
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw AccessibilityError.actionFailed(-1)
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw AccessibilityError.actionFailed(-1)
        }

        tagAsSyntheticForInputLock(keyDown)
        tagAsSyntheticForInputLock(keyUp)

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func tagAsSyntheticForInputLock(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: InputLockService.passthroughTag)
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
