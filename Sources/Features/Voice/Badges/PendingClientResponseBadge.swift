import SwiftUI

struct PendingClientResponseBadge: View {
    let pendingCount: Int
    let onOpen: () -> Void
    let title: String
    let dotColor: Color
    let dotStrokeColor: Color?
    let backgroundColor: Color
    let helpText: String

    var body: some View {
        if pendingCount <= 0 {
            EmptyView()
        } else {
            Button {
                onOpen()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .overlay {
                            if let dotStrokeColor {
                                Circle()
                                    .stroke(dotStrokeColor, lineWidth: 0.8)
                            }
                        }
                    Text("\(title) (\(pendingCount))")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(backgroundColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .help(helpText)
        }
    }
}

#Preview("Hidden") {
    PendingClientResponseBadge(
        pendingCount: 0,
        onOpen: {},
        title: "Client response pending",
        dotColor: .orange,
        dotStrokeColor: nil,
        backgroundColor: Color.orange.opacity(0.12),
        helpText: "Open client input"
    )
        .padding()
}

#Preview("Pending") {
    PendingClientResponseBadge(
        pendingCount: 2,
        onOpen: {},
        title: "Client response pending",
        dotColor: .orange,
        dotStrokeColor: nil,
        backgroundColor: Color.orange.opacity(0.12),
        helpText: "Open client input"
    )
        .padding()
}

struct WaitingForEventBadge: View {
    let pendingCount: Int
    let onOpen: () -> Void

    var body: some View {
        PendingClientResponseBadge(
            pendingCount: pendingCount,
            onOpen: onOpen,
            title: "Assistant waiting",
            dotColor: .white,
            dotStrokeColor: Color.black.opacity(0.22),
            backgroundColor: Color(nsColor: .controlBackgroundColor),
            helpText: "Open waiting event input"
        )
    }
}
