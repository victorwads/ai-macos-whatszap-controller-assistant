import SwiftUI
import WebKit

struct WhatsAppWebScreen: View {
    @EnvironmentObject private var appModel: AppModel

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

                    Button {
                        Task {
                            await appModel.captureWhatsAppWebSnapshot(for: account)
                        }
                    } label: {
                        Label("Refresh Snapshot", systemImage: "arrow.clockwise.circle")
                    }

                    Button {
                        Task {
                            await appModel.captureAndSaveWhatsAppWebSnapshot(for: account)
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

                        Text("State: \(snapshot.documentReadyState) • Logged in: \(snapshot.isLoggedIn ? "yes" : "no") • Chats: \(snapshot.chatRowCount) • Unread markers: \(snapshot.unreadBadgeCount)")
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
                description: Text("Create an account in Settings to keep a WhatsApp Web session running in the background.")
            )
        }
    }
}

private struct WhatsAppWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}

#Preview {
    WhatsAppWebScreen()
        .environmentObject(AppModel.preview)
        .frame(width: 1100, height: 720)
}
