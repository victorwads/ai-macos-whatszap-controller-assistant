import SwiftUI
import WebKit

struct WhatsAppWebScreen: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var captureNameDraft = ""

    var body: some View {
        detail
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                await appModel.loadWhatsAppWebAccounts()
            }
    }

    @ViewBuilder
    private var detail: some View {
        if let account = appModel.selectedWhatsAppWebAccount {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.name)
                            .font(.headline)
                        Text("https://web.whatsapp.com")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    TextField("Capture name", text: $captureNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)

                    Button {
                        Task {
                            await appModel.captureWhatsAppWebSnapshot(for: account)
                        }
                    } label: {
                        Label("Refresh Snapshot", systemImage: "arrow.clockwise.circle")
                    }

                    Button {
                        Task {
                            await appModel.forceUpdateSelectedWhatsAppWebChat(for: account)
                        }
                    } label: {
                        Label("Update This Chat", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button {
                        Task {
                            let trimmedName = captureNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            await appModel.captureAndSaveWhatsAppWebSnapshot(for: account, named: trimmedName.isEmpty ? nil : trimmedName)
                            captureNameDraft = ""
                        }
                    } label: {
                        Label("Save Snapshot", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        appModel.whatsAppWebDebugCaptureService.revealCapturesDirectoryInFinder()
                    } label: {
                        Label("Open Captures Folder", systemImage: "folder")
                    }
                }
                .padding(12)

                Divider()

                WhatsAppWebView(webView: appModel.whatsAppWebSessionStore.webView(for: account))
                    .id(account.id)

                if let snapshot = appModel.selectedWhatsAppWebPageSnapshot {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bridge Snapshot")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text("State: \(snapshot.documentReadyState) • Flow: \(snapshot.flow.rawValue) • Logged in: \(snapshot.isLoggedIn ? "yes" : "no") • Chats: \(snapshot.chatRowCount) • Unread markers: \(snapshot.unreadBadgeCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let selectedChatTitle = snapshot.selectedChatTitle, !selectedChatTitle.isEmpty {
                            Text("Selected chat: \(selectedChatTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let composePlaceholder = snapshot.composePlaceholder, !composePlaceholder.isEmpty {
                            Text("Composer: \(composePlaceholder)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
            }
        } else {
            ContentUnavailableView(
                "No WhatsApp Web account",
                systemImage: "globe",
                description: Text("Create an account from the home screen to keep a WhatsApp Web session running in the background.")
            )
        }
    }
}

private struct WhatsAppWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setFrameSize(Self.fixedViewportSize)
        webView.setContentHuggingPriority(.required, for: .horizontal)
        webView.setContentHuggingPriority(.required, for: .vertical)
        webView.setContentCompressionResistancePriority(.required, for: .horizontal)
        webView.setContentCompressionResistancePriority(.required, for: .vertical)

        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.widthAnchor.constraint(equalToConstant: Self.fixedViewportSize.width),
            webView.heightAnchor.constraint(equalToConstant: Self.fixedViewportSize.height)
        ])

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let targetSize = Self.fixedViewportSize
        if let embeddedWebView = container.subviews.compactMap({ $0 as? WKWebView }).first {
            if embeddedWebView.frame.size != targetSize {
                embeddedWebView.setFrameSize(targetSize)
            }
        }
    }

    static var fixedViewportSize: NSSize {
        NSSize(width: 1920, height: 1080)
    }
}

#Preview {
    WhatsAppWebScreen()
        .environmentObject(AppModel.preview)
        .frame(width: 1100, height: 720)
}
