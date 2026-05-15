import Foundation
@preconcurrency import ApplicationServices

/// Experimental global input lock using a CGEventTap.
/// This is intentionally scoped and time-bounded; misuse can make the machine feel "stuck".
final class InputLockService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var stopWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "assistantmcp.inputlock")

    func lockFor(seconds: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopLocked()
            self.startLocked()

            let workItem = DispatchWorkItem { [weak self] in
                self?.stopLocked()
            }
            self.stopWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + seconds, execute: workItem)
        }
    }

    func unlock() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    private func startLocked() {
        let mask = (
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )

        let callback: CGEventTapCallBack = { _, _, event, _ in
            // Swallow the event.
            Unmanaged.passUnretained(event)
            return nil
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: nil
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    private func stopLocked() {
        stopWorkItem?.cancel()
        stopWorkItem = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
    }
}

