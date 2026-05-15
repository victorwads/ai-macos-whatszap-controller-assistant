import SwiftUI

struct PendingClientResponseBadge: View {
    let pendingCount: Int
    let onOpen: () -> Void

    var body: some View {
        if pendingCount <= 0 {
            EmptyView()
        } else {
            Button {
                onOpen()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 8)
                    Text("Client response pending (\(pendingCount))")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Open Client Voice")
        }
    }
}

#Preview("Hidden") {
    PendingClientResponseBadge(pendingCount: 0, onOpen: {})
        .padding()
}

#Preview("Pending") {
    PendingClientResponseBadge(pendingCount: 2, onOpen: {})
        .padding()
}

