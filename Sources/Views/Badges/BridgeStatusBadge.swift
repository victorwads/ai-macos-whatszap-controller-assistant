import SwiftUI

struct BridgeStatusBadge: View {
    let accessibilityTrusted: Bool
    let whatsappRunning: Bool
    let onRequestAccessibilityPermission: () -> Void

    var body: some View {
        if accessibilityTrusted {
            StatusBadge(
                title: "WhatsApp \(whatsappRunning ? "Open" : "Closed")",
                isOnline: whatsappRunning,
                subtitle: nil,
                help: "Shows whether WhatsApp is currently running."
            )
        } else {
            Button {
                onRequestAccessibilityPermission()
            } label: {
                StatusBadge(
                    title: "Accessibility Error",
                    isOnline: false,
                    subtitle: "Click to grant",
                    help: "Accessibility permission is required. Click to request it."
                )
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("OK / Open") {
    BridgeStatusBadge(
        accessibilityTrusted: true,
        whatsappRunning: true,
        onRequestAccessibilityPermission: {}
    )
    .padding()
}

#Preview("OK / Closed") {
    BridgeStatusBadge(
        accessibilityTrusted: true,
        whatsappRunning: false,
        onRequestAccessibilityPermission: {}
    )
    .padding()
}

#Preview("Needs Accessibility") {
    BridgeStatusBadge(
        accessibilityTrusted: false,
        whatsappRunning: false,
        onRequestAccessibilityPermission: {}
    )
    .padding()
}

