import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedScreen: SidebarScreen = .conversations
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum SidebarScreen: String, CaseIterable, Identifiable {
        case conversations
        case nicknames
        case integrationLogs
        case integrationDebug
        case serverLogs
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .conversations: "Conversations"
            case .nicknames: "Nicknames"
            case .integrationLogs: "Logs"
            case .integrationDebug: "Debug"
            case .serverLogs: "Server Logs"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .conversations: "bubble.left.and.bubble.right"
            case .nicknames: "tag"
            case .integrationLogs: "list.bullet.rectangle"
            case .integrationDebug: "point.3.connected.trianglepath.dotted"
            case .serverLogs: "server.rack"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: Binding(get: { selectedScreen }, set: { selectedScreen = $0 ?? selectedScreen })) {
                Section("Data") {
                    sidebarItem(.conversations)
                    sidebarItem(.nicknames)
                }

                Section("Integration") {
                    sidebarItem(.integrationLogs)
                    sidebarItem(.integrationDebug)
                }

                Section("Server") {
                    sidebarItem(.serverLogs)
                }

                Section("Settings") {
                    sidebarItem(.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 360)
            .navigationTitle("Assistant MCP")
        } detail: {
            VStack(spacing: 0) {
                headerBar
                Divider()
                selectedDetailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var selectedDetailView: some View {
        Group {
            switch selectedScreen {
            case .conversations:
                ConversationsScreen()
            case .nicknames:
                NicknamesScreen()
            case .settings:
                SettingsScreen(appModel: appModel)
                    .padding(12)
            case .integrationLogs:
                LogsScreen()
            case .integrationDebug:
                DebugTreeScreen()
            case .serverLogs:
                ServerLogsScreen()
            }
        }
    }

    private func sidebarItem(_ screen: SidebarScreen) -> some View {
        Label(screen.title, systemImage: screen.systemImage)
            .tag(screen)
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text(selectedScreen.title)
                .font(.title3.weight(.semibold))

            Spacer()

            BridgeStatusBadge(
                accessibilityTrusted: appModel.accessibilityTrusted,
                whatsappRunning: appModel.whatsappRunning,
                onRequestAccessibilityPermission: {
                    appModel.requestAccessibilityPermission()
                }
            )

            MCPServerStatusBadge(
                isRunning: appModel.mcpServerRunning,
                address: appModel.mcpServerAddress,
                statusDescription: appModel.mcpServerStatusDescription
            )

            Text(appModel.lastRefreshDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}
