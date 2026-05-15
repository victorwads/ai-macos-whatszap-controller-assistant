import AppKit
import AVFoundation
import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var appModel: AppModel
    @State private var isReadingInstructions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                    Text("Applies to local UI behavior and MCP tool handling.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Polling") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Interval")
                            Spacer()
                            Stepper(value: $appModel.pollingIntervalSeconds, in: 1...30) {
                                Text("\(appModel.pollingIntervalSeconds)s")
                                    .monospacedDigit()
                            }
                            .frame(width: 140, alignment: .trailing)
                        }

                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await appModel.refreshConversations()
                                }
                            } label: {
                                Label("Refresh Chats", systemImage: "list.bullet.rectangle")
                            }

                            Button {
                                if appModel.isPolling {
                                    appModel.stopPolling()
                                } else {
                                    appModel.startPolling()
                                }
                            } label: {
                                Label(appModel.isPolling ? "Stop Polling" : "Start Polling", systemImage: appModel.isPolling ? "pause.circle" : "play.circle")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Accessibility") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button {
                                appModel.requestAccessibilityPermission()
                            } label: {
                                Label(appModel.waitingForAccessibilityRelaunch ? "Waiting Permission" : "Permission", systemImage: appModel.waitingForAccessibilityRelaunch ? "hourglass" : "lock.open")
                            }
                            .disabled(appModel.waitingForAccessibilityRelaunch)

                            Button {
                                appModel.dumpWhatsAppSnapshot()
                            } label: {
                                Label("Dump WhatsApp", systemImage: "doc.text.magnifyingglass")
                            }
                        }

                        HStack(spacing: 8) {
                            Toggle("Experimental Input Lock (5s during send)", isOn: $appModel.experimentalInputLockEnabled)
                                .toggleStyle(.switch)

                            Button {} label: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Experimental. This can temporarily block mouse and keyboard input during message send (up to 5 seconds).")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Conversation Access") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Policy")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Picker("Policy", selection: $appModel.conversationAccessMode) {
                            ForEach(ConversationAccessMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Text(appModel.conversationAccessMode.helpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        HStack {
                            Text("Allow list: \(appModel.allowConversationNames.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Deny list: \(appModel.denyConversationNames.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        Text("Edit allow/deny lists from the Conversations screen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("MCP Server") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Host")
                            Spacer()
                            TextField("Host", text: $appModel.mcpServerHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                        }

                        HStack {
                            Text("Port")
                            Spacer()
                            TextField(
                                "8080",
                                text: Binding(
                                    get: { appModel.mcpServerPortText },
                                    set: { appModel.updateMCPServerPortText($0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        }

                        Text("Address: \(appModel.mcpServerAddress)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(appModel.mcpServerStatusDescription)
                            .font(.caption)
                            .foregroundStyle(appModel.mcpServerRunning ? .green : .secondary)

                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await appModel.restartMCPServer()
                                }
                            } label: {
                                Label(appModel.mcpServerRunning ? "Restart Server" : "Start Server", systemImage: "bolt.horizontal.circle")
                            }

                            if appModel.mcpServerRunning {
                                Button {
                                    Task {
                                        await appModel.stopMCPServer()
                                    }
                                } label: {
                                    Label("Stop Server", systemImage: "stop.circle")
                                }
                            }
                        }

                        Text("Client snippet")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextEditor(text: .constant(appModel.mcpConfigurationSnippet))
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 150)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2))
                            )

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(appModel.mcpConfigurationSnippet, forType: .string)
                        } label: {
                            Label("Copy MCP Snippet", systemImage: "doc.on.doc")
                        }

                        Divider()

                        Text("Outgoing messages")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Prefix")
                            Spacer()
                            TextField("e.g. Robozinho: ", text: $appModel.mcpSendMessagePrefix)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                        }

                        Text("Applied only to MCP tool `send_message` (not to manual sends from the UI).")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        HStack {
                            Text("Instructions")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Reset to Default") {
                                appModel.assistantInstructions = AppModel.defaultAssistantInstructions
                            }
                        }

                        TextEditor(text: $appModel.assistantInstructions)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 220)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2))
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Assistant") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Voice")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Recognition")
                            Spacer()
                            Picker("Recognition", selection: $appModel.recognitionLocaleIdentifier) {
                                ForEach(appModel.availableRecognitionLocales, id: \.identifier) { locale in
                                    Text(locale.identifier).tag(locale.identifier)
                                }
                            }
                            .frame(width: 220, alignment: .trailing)
                        }

                        HStack {
                            Text("Speech language")
                            Spacer()
                            Picker("Speech language", selection: $appModel.speechLanguage) {
                                ForEach(appModel.availableSpeechLanguages, id: \.self) { language in
                                    Text(language).tag(language)
                                }
                            }
                            .frame(width: 220, alignment: .trailing)
                        }

                        HStack {
                            Text("Voice")
                            Spacer()
                            let voices = appModel.availableSpeechVoices(forLanguage: appModel.speechLanguage)
                            Picker("Voice", selection: Binding<String>(
                                get: { appModel.speechVoiceIdentifier ?? "" },
                                set: { appModel.speechVoiceIdentifier = $0.isEmpty ? nil : $0 }
                            )) {
                                Text("Auto").tag("")
                                ForEach(voices, id: \.identifier) { voice in
                                    Text("\(voice.name)\(voice.quality == .enhanced ? " (Enhanced)" : "")").tag(voice.identifier)
                                }
                            }
                            .frame(width: 360, alignment: .trailing)
                        }

                        HStack {
                            Text("Rate")
                            Spacer()
                            Slider(value: $appModel.speechRate, in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
                                .frame(width: 220)
                            Text(String(format: "%.2f", appModel.speechRate))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }

                        Toggle("Hands-free Client Voice window", isOn: $appModel.handsFreeClientVoiceEnabled)
                            .toggleStyle(.switch)
                            .help("When enabled (default), opening a pending client ask will bring a floating window to the front and start voice recognition with auto-submit.")

                        Button {
                            let text = appModel.assistantInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            if isReadingInstructions {
                                isReadingInstructions = false
                                Task {
                                    await appModel.voiceAssistant.stopSpeaking()
                                }
                            } else {
                                isReadingInstructions = true
                                Task {
                                    await appModel.voiceAssistant.speak(
                                        text,
                                        language: appModel.speechLanguage,
                                        voiceIdentifier: appModel.speechVoiceIdentifier,
                                        rate: appModel.speechRate
                                    )
                                }
                            }
                        } label: {
                            Label(isReadingInstructions ? "Stop" : "Test (Read Instructions)", systemImage: isReadingInstructions ? "stop.fill" : "speaker.wave.2.fill")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .topLeading)
        }
    }
}
