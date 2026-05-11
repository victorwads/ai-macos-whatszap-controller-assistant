import SwiftUI

struct LogView: View {
    let logs: [LogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(logs) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .foregroundStyle(.secondary)
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 72, alignment: .leading)

                            Text(entry.level.rawValue.uppercased())
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .foregroundStyle(entry.level.color)
                                .frame(width: 56, alignment: .leading)

                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .id(entry.id)
                    }
                }
                .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: logs.count) {
                guard let last = logs.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
