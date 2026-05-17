import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedScreen: SidebarScreen = .whatsAppChats
    @State private var selectedSubjectId: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum SidebarScreen: Hashable, Identifiable {
        case nicknames
        case subjects
        case memories
        case sensitiveData
        case clientVoice
        case whatsAppChats
        case whatsAppWebAccount(UUID)
        case integrationLogs
        case integrationDebug
        case serverLogs
        case serverTools
        case settings

        var id: String {
            switch self {
            case .nicknames: "nicknames"
            case .subjects: "subjects"
            case .memories: "memories"
            case .sensitiveData: "sensitiveData"
            case .clientVoice: "clientVoice"
            case .whatsAppChats: "whatsAppChats"
            case .whatsAppWebAccount(let id): "whatsAppWebAccount:\(id.uuidString)"
            case .integrationLogs: "integrationLogs"
            case .integrationDebug: "integrationDebug"
            case .serverLogs: "serverLogs"
            case .serverTools: "serverTools"
            case .settings: "settings"
            }
        }

        var defaultTitle: String {
            switch self {
            case .nicknames: "Nicknames"
            case .subjects: "Subjects"
            case .memories: "Memories"
            case .sensitiveData: "Sensitive Data"
            case .clientVoice: "Client Voice"
            case .whatsAppChats: "WhatsApp"
            case .whatsAppWebAccount: "WhatsApp Web"
            case .integrationLogs: "Logs"
            case .integrationDebug: "Debug"
            case .serverLogs: "Logs"
            case .serverTools: "Tools"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .nicknames: "tag"
            case .subjects: "checklist"
            case .memories: "brain"
            case .sensitiveData: "lock.shield"
            case .clientVoice: "waveform"
            case .whatsAppChats: "bubble.left.and.bubble.right"
            case .whatsAppWebAccount: "globe"
            case .integrationLogs: "list.bullet.rectangle"
            case .integrationDebug: "point.3.connected.trianglepath.dotted"
            case .serverLogs: "server.rack"
            case .serverTools: "wrench.and.screwdriver"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: Binding(get: { selectedScreen }, set: { handleSidebarSelection($0) })) {
                Section("Data") {
                    sidebarItem(.nicknames)
                    sidebarItem(.subjects)
                    sidebarItem(.memories)
                    sidebarItem(.sensitiveData)
                    sidebarItem(.clientVoice)
                }

                Section("WhatsApp Integration") {
                    sidebarItem(.whatsAppChats)
                    ForEach(appModel.whatsAppWebAccounts) { account in
                        sidebarItem(.whatsAppWebAccount(account.id), title: account.name)
                    }
                    sidebarItem(.integrationLogs)
                    sidebarItem(.integrationDebug)
                }

                Section("Server") {
                    sidebarItem(.serverLogs)
                    sidebarItem(.serverTools)
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
                SubjectsScreen(selectedSubjectId: $selectedSubjectId)
            case .memories:
                MemoriesScreen()
            case .sensitiveData:
                SensitiveDataScreen { subjectId in
                    if let subjectUUID = UUID(uuidString: subjectId) {
                        selectedSubjectId = subjectUUID
                    }
                    selectedScreen = .subjects
                }
            case .clientVoice:
                ClientVoiceScreen()
            case .whatsAppChats:
                ConversationsScreen()
            case .whatsAppWebAccount(let accountId):
                let _ = syncSelectedWhatsAppWebAccount(with: accountId)
                WhatsAppWebScreen()
            case .settings:
                SettingsScreen(
                    appModel: appModel,
                    voiceSettings: appModel.voiceSettings,
                    handsFreeClientVoiceSettings: appModel.handsFreeClientVoiceSettings,
                    inputLockSettings: appModel.inputLockSettings,
                    mcpSendPrefixSettings: appModel.mcpSendPrefixSettings,
                    whatsAppWebSettings: appModel.whatsAppWebSettings
                )
                    .padding(12)
            case .integrationLogs:
                LogsScreen()
            case .integrationDebug:
                DebugTreeScreen(
                    captureService: appModel.whatsAppDebugService,
                    accessibility: appModel.accessibility
                )
            case .serverLogs:
                ServerLogsScreen()
            case .serverTools:
                ServerToolsScreen()
            }
        }
    }

    private func sidebarItem(_ screen: SidebarScreen, title: String? = nil) -> some View {
        Label(title ?? screen.defaultTitle, systemImage: screen.systemImage)
            .tag(screen)
    }

    private func handleSidebarSelection(_ screen: SidebarScreen?) {
        guard let screen else { return }
        selectedScreen = screen

        if case .whatsAppWebAccount(let accountId) = screen {
            appModel.selectedWhatsAppWebAccountId = accountId
        }
    }

    @discardableResult
    private func syncSelectedWhatsAppWebAccount(with accountId: UUID) -> Bool {
        if appModel.selectedWhatsAppWebAccountId != accountId {
            appModel.selectedWhatsAppWebAccountId = accountId
        }
        return true
    }

    private var selectedScreenTitle: String {
        switch selectedScreen {
        case .whatsAppWebAccount(let accountId):
            return appModel.whatsAppWebAccounts.first(where: { $0.id == accountId })?.name ?? selectedScreen.defaultTitle
        default:
            return selectedScreen.defaultTitle
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text(selectedScreenTitle)
                .font(.title3.weight(.semibold))

            Spacer()

            SpeechStatusBadge(
                isSpeaking: appModel.speechSynthesizerSpeaking,
                onStop: {
                    Task { await appModel.voiceAssistant.stopSpeaking() }
                }
            )

            PendingClientResponseBadge(
                pendingCount: appModel.pendingClientAskCount,
                onOpen: {
                    Task {
                        await appModel.openPendingClientAskWindow()
                    }
                },
                title: "Client response pending",
                dotColor: .orange,
                dotStrokeColor: nil,
                backgroundColor: Color.orange.opacity(0.12),
                helpText: "Open pending client ask"
            )

            WaitingForEventBadge(
                pendingCount: appModel.pendingClientPromptWaitCount,
                onOpen: {
                    appModel.openPendingClientPromptWindow()
                }
            )

            MicrophonePermissionBadge(
                isAuthorized: appModel.microphoneAuthorized,
                speechRecognitionAuthorized: appModel.speechRecognitionAuthorized,
                onRequestPermission: {
                    Task { await appModel.requestVoicePermissions() }
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

#Preview {
    ContentView()
        .environmentObject(AppModel.preview)
        .frame(width: 980, height: 680)
}
