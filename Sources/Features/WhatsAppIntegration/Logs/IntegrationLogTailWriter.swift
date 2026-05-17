import Foundation

/// Keeps a rolling tail of recent integration logs on disk so we can inspect failures
/// even when the UI log view is inconvenient to copy.
actor IntegrationLogTailWriter {
    static let shared = IntegrationLogTailWriter()

    private let maxEntries: Int
    private let fileURL: URL
    private var entries: [String] = []

    init(
        maxEntries: Int = 200,
        fileURL: URL = URL(fileURLWithPath: "/private/tmp/AssistantMCPServer/logs/whatsapp-integration-tail.txt")
    ) {
        self.maxEntries = max(10, maxEntries)
        self.fileURL = fileURL
    }

    func append(entry: LogEntry) {
        let ts = entry.timestamp.formatted(date: .omitted, time: .standard)
        let line = "[\(ts)] [\(entry.level.rawValue.uppercased())] \(entry.message)"
        entries.append(line)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist()
    }

    private func persist() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let text = entries.joined(separator: "\n") + "\n"
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            // Avoid recursive logging; best-effort persistence only.
        }
    }
}

