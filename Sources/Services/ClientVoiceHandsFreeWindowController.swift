import AppKit
import SwiftUI

@MainActor
final class ClientVoiceHandsFreeWindowController: NSWindowController {
    static let shared = ClientVoiceHandsFreeWindowController()

    private var currentAskId: UUID?

    func show(
        appModel: AppModel,
        askId: UUID,
        prompt: String
    ) {
        if currentAskId == askId, let window {
            NSApp.activate(ignoringOtherApps: true)
            window.center()
            window.makeKeyAndOrderFront(nil)
            return
        }

        currentAskId = askId

        let rootView = ClientVoiceHandsFreeWindow(
            appModel: appModel,
            voiceSettings: appModel.voiceSettings,
            askId: askId,
            prompt: prompt,
            onDone: { [weak self] in
                self?.close()
            }
        )
        .frame(width: 560, height: 220)

        let hosting = NSHostingView(rootView: rootView)

        let window: NSWindow
        if let existing = self.window {
            window = existing
            window.contentView = hosting
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 220),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Client Voice"
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = hosting
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    override func close() {
        currentAskId = nil
        super.close()
    }
}
