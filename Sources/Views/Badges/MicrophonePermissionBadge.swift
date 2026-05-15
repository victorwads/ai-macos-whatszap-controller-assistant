import SwiftUI

struct MicrophonePermissionBadge: View {
    let isAuthorized: Bool
    let onRequestPermission: () -> Void

    var body: some View {
        if isAuthorized {
            EmptyView()
        } else {
            Button {
                onRequestPermission()
            } label: {
                StatusBadge(
                    title: "Microphone",
                    isOnline: false,
                    subtitle: "Click to grant",
                    help: "Microphone permission is required for voice answers. Click to request it."
                )
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("Authorized (hidden)") {
    MicrophonePermissionBadge(isAuthorized: true, onRequestPermission: {})
        .padding()
}

#Preview("Not authorized") {
    MicrophonePermissionBadge(isAuthorized: false, onRequestPermission: {})
        .padding()
}

