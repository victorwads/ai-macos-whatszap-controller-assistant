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
                }
                .padding(12)

                Divider()

                WhatsAppWebView(webView: appModel.whatsAppWebSessionStore.webView(for: account))
                    .id(account.id)
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
