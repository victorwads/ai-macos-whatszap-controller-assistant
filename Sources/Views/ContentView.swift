import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedScreen: SidebarScreen = .whatsAppChats
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum SidebarScreen: String, CaseIterable, Identifiable {
        case nicknames
        case subjects
        case memories
        case clientVoice
        case whatsAppChats
        case integrationLogs
        case integrationDebug
        case serverLogs
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nicknames: "Nicknames"
            case .subjects: "Subjects"
            case .memories: "Memories"
            case .clientVoice: "Client Voice"
            case .whatsAppChats: "WhatsApp"
            case .integrationLogs: "Logs"
            case .integrationDebug: "Debug"
            case .serverLogs: "Logs"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .nicknames: "tag"
            case .subjects: "checklist"
            case .memories: "brain"
            case .clientVoice: "waveform"
            case .whatsAppChats: "bubble.left.and.bubble.right"
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
                    sidebarItem(.nicknames)
                    sidebarItem(.subjects)
                    sidebarItem(.memories)
                    sidebarItem(.clientVoice)
                }

                Section("WhatsApp Integration") {
                    sidebarItem(.whatsAppChats)
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
            case .nicknames:
                NicknamesScreen()
            case .subjects:
                SubjectsScreen()
            case .memories:
                MemoriesScreen()
            case .clientVoice:
                ClientVoiceScreen()
            case .whatsAppChats:
                ConversationsScreen()
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

            PendingClientResponseBadge(
                pendingCount: appModel.pendingClientAskCount,
                onOpen: { selectedScreen = .clientVoice }
            )

            MicrophonePermissionBadge(
                isAuthorized: appModel.microphoneAuthorized,
                onRequestPermission: {
                    Task { await appModel.requestMicrophonePermission() }
                }
            )

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
