import SwiftUI

@main
struct AssistantMCPServerApp: App {
    @StateObject private var appModel: AppModel

    init() {
        let storedBasePort = UserDefaults.standard.integer(forKey: "mcpServer.basePort.v1")
        let basePort = (1024...65535).contains(storedBasePort) ? storedBasePort : 8080
        _appModel = StateObject(wrappedValue: AppModel(
            profile: .default,
            profileIndex: 0,
            basePort: basePort,
            primaryWhatsAppWebAccountId: nil,
            startupMode: .home
        ))
    }

    var body: some Scene {
        WindowGroup {
            ProfilesHomeScreen()
                .environmentObject(appModel)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
    }
}
