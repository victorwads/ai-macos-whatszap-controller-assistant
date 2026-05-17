import SwiftUI

struct ProfilesHomeScreen: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var profileWindowManager = ProfileWindowManager.shared
    @State private var newProfileName = ""
    @State private var isAddingProfile = false
    @State private var didBootstrap = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                GroupBox {
                    VStack(spacing: 0) {
                        if appModel.whatsAppWebAccounts.isEmpty {
                            emptyState
                        } else {
                            ForEach(Array(appModel.whatsAppWebAccounts.enumerated()), id: \.element.id) { index, account in
                                ProfileRow(
                                    account: account,
                                    port: appModel.mcpServerPort + index,
                                    isRunning: profileWindowManager.isProfileRunning(profileId: profileId(for: account)),
                                    onToggleAutoStart: { isOn in
                                        Task {
                                            await appModel.updateWhatsAppWebAccountAutoStart(id: account.id, isAutoStart: isOn)
                                        }
                                    },
                                    onStartStop: {
                                        Task {
                                            await toggleProfile(account: account, index: index)
                                        }
                                    },
                                    onDelete: {
                                        Task {
                                            await deleteProfile(account: account)
                                        }
                                    }
                                )

                                if index < appModel.whatsAppWebAccounts.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                } label: {
                    Label("Perfis", systemImage: "bubble.left.and.person.crop.circle")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add a new profile")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            TextField("Profile name", text: $newProfileName)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                Task {
                                    await addProfile()
                                }
                            } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .disabled(isAddingProfile || newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        Text("Auto start is configured directly in the list above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Novo perfil", systemImage: "plus.rectangle.on.rectangle")
                }
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .topLeading)
        }
        .navigationTitle("Assistant MCP")
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await appModel.loadWhatsAppWebAccounts()
            await bootstrapAutoStartIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Profiles")
                .font(.largeTitle.weight(.semibold))
            Text("Choose which profile to start, whether it should auto start next time, and which port it uses for MCP.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Base MCP port: \(appModel.mcpServerPort)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No profiles yet.")
                .font(.headline)
            Text("Create the first profile above, then start it manually or mark it for auto start on the next launch.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private func profileId(for account: WhatsAppWebAccount) -> String {
        AppProfile.forWhatsAppWebAccount(account, isDefault: false).id
    }

    @MainActor
    private func toggleProfile(account: WhatsAppWebAccount, index: Int) async {
        let profile = AppProfile.forWhatsAppWebAccount(account, isDefault: false)
        if profileWindowManager.isProfileRunning(profileId: profile.id) {
            await profileWindowManager.stopMainWindow(profileId: profile.id)
            return
        }

        let model = AppModel(
            profile: profile,
            profileIndex: index,
            basePort: appModel.mcpServerPort,
            primaryWhatsAppWebAccountId: account.id,
            startupMode: .live
        )
        profileWindowManager.showMainWindow(profile: profile, appModel: model)
    }

    @MainActor
    private func deleteProfile(account: WhatsAppWebAccount) async {
        let profileId = profileId(for: account)
        if profileWindowManager.isProfileRunning(profileId: profileId) {
            await profileWindowManager.stopMainWindow(profileId: profileId)
        }

        await appModel.deleteWhatsAppWebAccount(id: account.id)
    }

    @MainActor
    private func addProfile() async {
        let trimmedName = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isAddingProfile = true
        defer { isAddingProfile = false }

        await appModel.addWhatsAppWebAccount(named: trimmedName)
        newProfileName = ""
    }

    @MainActor
    private func bootstrapAutoStartIfNeeded() async {
        let accounts = appModel.whatsAppWebAccounts
        guard !accounts.isEmpty else { return }

        for (index, account) in accounts.enumerated() where account.isAutoStart {
            let profile = AppProfile.forWhatsAppWebAccount(account, isDefault: false)
            guard !profileWindowManager.isProfileRunning(profileId: profile.id) else {
                continue
            }

            let model = AppModel(
                profile: profile,
                profileIndex: index,
                basePort: appModel.mcpServerPort,
                primaryWhatsAppWebAccountId: account.id,
                startupMode: .live
            )
            profileWindowManager.showMainWindow(profile: profile, appModel: model)
        }
    }
}

private struct ProfileRow: View {
    let account: WhatsAppWebAccount
    let port: Int
    let isRunning: Bool
    let onToggleAutoStart: (Bool) -> Void
    let onStartStop: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: "person.fill")
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text("MCP port \(port)")
                    Text("•")
                    Text(isRunning ? "Running" : "Stopped")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle("Auto start", isOn: Binding(
                get: { account.isAutoStart },
                set: { onToggleAutoStart($0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help("Start this profile automatically when the app opens.")

            Button {
                onStartStop()
            } label: {
                Label(isRunning ? "Stop" : "Start", systemImage: isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this profile")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}

#Preview {
    ProfilesHomeScreen()
        .environmentObject(AppModel(profile: .default, profileIndex: 0, basePort: 8080, startupMode: .home))
        .frame(width: 980, height: 720)
}
