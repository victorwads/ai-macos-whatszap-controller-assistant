import AppKit
import SwiftUI

@MainActor
final class ClientVoicePromptWindowController: NSWindowController {
    static let shared = ClientVoicePromptWindowController()

    func show(appModel: AppModel) {
        let rootView = ClientVoicePromptWindow(
            appModel: appModel,
            voiceSettings: appModel.voiceSettings,
            onDone: { [weak self] in
                self?.close()
            }
        )
        .frame(width: 560, height: 190)

        let hosting = NSHostingView(rootView: rootView)

        let window: NSWindow
        if let existing = self.window {
            window = existing
            window.contentView = hosting
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 190),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Client Prompt"
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
}
