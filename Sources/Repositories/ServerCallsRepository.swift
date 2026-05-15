import Foundation

actor ServerCallsRepository {
    static let shared = ServerCallsRepository()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var cachedURL: URL?

    func append(_ entry: MCPServerCallEntry) {
        do {
            let url = try resolveURL()
            let data = try encoder.encode(entry)
            try appendLine(data: data, to: url)
        } catch {
            // Best-effort persistence; runtime logs already exist elsewhere.
        }
    }

    func loadAll() -> [MCPServerCallEntry] {
        do {
            let url = try resolveURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            var entries: [MCPServerCallEntry] = []
            entries.reserveCapacity(512)
            for line in text.split(separator: "\n") {
                guard !line.isEmpty else { continue }
                if let decoded = try? decoder.decode(MCPServerCallEntry.self, from: Data(line.utf8)) {
                    entries.append(decoded)
                }
            }
            return entries
        } catch {
            return []
        }
    }

    func clear() {
        do {
            let url = try resolveURL()
            try? FileManager.default.removeItem(at: url)
        } catch {
            // ignore
        }
    }

    private func resolveURL() throws -> URL {
        if let cachedURL { return cachedURL }

        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directory = appSupport.appendingPathComponent("AssistantMCPServer/Logs", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("server_calls.jsonl", isDirectory: false)
        cachedURL = url
        return url
    }

    private func appendLine(data: Data, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
    }
}

