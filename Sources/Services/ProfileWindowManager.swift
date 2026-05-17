import AppKit
import SwiftUI

@MainActor
final class ProfileWindowManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ProfileWindowManager()

    private var controllersByProfileId: [String: NSWindowController] = [:]
    private var appModelsByProfileId: [String: AppModel] = [:]
    private var profileIdsByWindowId: [ObjectIdentifier: String] = [:]
    @Published private(set) var runningProfileIds: Set<String> = []

    func showMainWindow(profile: AppProfile, appModel: AppModel) {
        appModelsByProfileId[profile.id] = appModel

        if let existing = controllersByProfileId[profile.id], let window = existing.window {
            runningProfileIds.insert(profile.id)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ContentView()
            .environmentObject(appModel)
            .frame(minWidth: 980, minHeight: 680)

        let hosting = NSHostingView(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Assistant MCP — \(profile.displayName)"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        profileIdsByWindowId[ObjectIdentifier(window)] = profile.id
        runningProfileIds.insert(profile.id)

        let controller = NSWindowController(window: window)
        controllersByProfileId[profile.id] = controller

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func stopMainWindow(profileId: String) async {
        guard let controller = controllersByProfileId.removeValue(forKey: profileId) else {
            runningProfileIds.remove(profileId)
            let appModel = appModelsByProfileId.removeValue(forKey: profileId)
            await appModel?.shutdown()
            return
        }

        runningProfileIds.remove(profileId)
        let appModel = appModelsByProfileId.removeValue(forKey: profileId)
        if let window = controller.window {
            profileIdsByWindowId.removeValue(forKey: ObjectIdentifier(window))
        }

        await appModel?.shutdown()
        controller.close()
    }

    func isProfileRunning(profileId: String) -> Bool {
        runningProfileIds.contains(profileId)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        let windowId = ObjectIdentifier(window)
        guard let profileId = profileIdsByWindowId.removeValue(forKey: windowId) else {
            return
        }

        runningProfileIds.remove(profileId)
        controllersByProfileId.removeValue(forKey: profileId)

        let appModel = appModelsByProfileId.removeValue(forKey: profileId)
        Task { await appModel?.shutdown() }
    }
}
