import SwiftUI

struct MCPServerStatusBadge: View {
    let isRunning: Bool
    let address: String
    let statusDescription: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(address)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule())
        .help("MCP \(isRunning ? "Online" : "Offline")\n\(statusDescription)")
    }
}
