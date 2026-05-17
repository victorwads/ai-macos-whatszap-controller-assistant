import AppKit
import Foundation

private let defaultWhatsAppWebDebugDirectory = URL(fileURLWithPath: "/tmp/AssistantMCPServer", isDirectory: true)

@MainActor
final class WhatsAppWebDebugCaptureService {
    private let debugDirectory: URL
    private let log: (String, LogLevel) -> Void

    init(
        debugDirectory: URL = defaultWhatsAppWebDebugDirectory,
        log: @escaping (String, LogLevel) -> Void
    ) {
        self.debugDirectory = debugDirectory
        self.log = log
    }

    func capturesDirectoryURL() -> URL {
        debugDirectory
            .appendingPathComponent("captures", isDirectory: true)
            .appendingPathComponent("whatsapp-web", isDirectory: true)
    }

    func revealCapturesDirectoryInFinder() {
        do {
            let capturesDirectory = capturesDirectoryURL()
            try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)

            if NSWorkspace.shared.open(capturesDirectory) {
                return
            }

            NSWorkspace.shared.activateFileViewerSelecting([capturesDirectory])
        } catch {
            log("Failed to reveal WhatsApp Web captures directory: \(error.localizedDescription)", .warning)
        }
    }

    func saveSnapshot(accountName: String, snapshot: WhatsAppWebPageSnapshot) -> URL? {
        do {
            let capturesDirectory = capturesDirectoryURL()
            try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)

            let timestamp = Self.debugCaptureTimestamp(Date())
            let slug = Self.debugCaptureFileSlug(accountName)
            let fileURL = capturesDirectory.appendingPathComponent("\(timestamp)-\(slug).yaml")
            let contents = WhatsAppWebDebugArtifacts.captureYAML(accountName: accountName, snapshot: snapshot)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            log("Saved WhatsApp Web debug capture to \(fileURL.path).", .info)
            return fileURL
        } catch {
            log("Failed to save WhatsApp Web debug capture: \(error.localizedDescription)", .warning)
            return nil
        }
    }

    private static func debugCaptureTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    private static func debugCaptureFileSlug(_ value: String) -> String {
        let lowered = value.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }

        let collapsed = String(mapped)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return collapsed.isEmpty ? "capture" : collapsed
    }
}
