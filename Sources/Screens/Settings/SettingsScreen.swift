import AppKit
import AVFoundation
import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var appModel: AppModel
    @State private var isReadingInstructions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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

                        Toggle("Experimental Input Lock (5s during send)", isOn: $appModel.experimentalInputLockEnabled)
                            .toggleStyle(.switch)
                            .help("Experimental. This can temporarily block mouse and keyboard input during message send (up to 5 seconds).")
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
        }
    }
}
