import Foundation

private let defaultWhatsAppDebugDirectory = URL(fileURLWithPath: "/tmp/AssistantMCPServer", isDirectory: true)

@MainActor
final class WhatsAppDebugCaptureService {
    private let accessibility: AccessibilityService
    private let parser: WhatsAppAppParser
    private let debugDirectory: URL
    private let log: (String, LogLevel) -> Void

    init(
        accessibility: AccessibilityService,
        parser: WhatsAppAppParser,
        debugDirectory: URL = defaultWhatsAppDebugDirectory,
        log: @escaping (String, LogLevel) -> Void
    ) {
        self.accessibility = accessibility
        self.parser = parser
        self.debugDirectory = debugDirectory
        self.log = log
    }

    func captureSnapshot(maxDepth: Int = 14) -> WhatsAppSnapshot? {
        guard prepareForWhatsAppInspection() else {
            return nil
        }

        do {
            return try accessibility.captureWhatsAppSnapshot(maxDepth: maxDepth)
        } catch {
            log("Failed to capture WhatsApp snapshot: \(error.localizedDescription)", .error)
            return nil
        }
    }

    func saveDebugSnapshot(
        named rawName: String,
        focusPath: [Int],
        snapshot: WhatsAppSnapshot,
        messageLimit: Int = 10
    ) {
        let captureName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = captureName.isEmpty ? "capture" : captureName
        let screenState = parser.parse(snapshot: snapshot, messageLimit: messageLimit)

        do {
            let capturesDirectory = debugDirectory.appendingPathComponent("captures", isDirectory: true)
            try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)

            let timestamp = Self.debugCaptureTimestamp(Date())
            let slug = Self.debugCaptureFileSlug(effectiveName)
            let fileURL = capturesDirectory.appendingPathComponent("\(timestamp)-\(slug).yaml")
            let contents = WhatsAppDebugArtifacts.captureYAML(
                name: effectiveName,
                focusPath: focusPath,
                snapshot: snapshot,
                screenState: screenState
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)

            log("Saved WhatsApp debug capture to \(fileURL.path).", .info)
        } catch {
            log("Failed to save debug capture: \(error.localizedDescription)", .warning)
        }
    }

    private func prepareForWhatsAppInspection() -> Bool {
        let trustedNow = accessibility.isTrusted(prompt: false)
        guard trustedNow else {
            log("Cannot inspect WhatsApp before Accessibility permission is granted to this exact app binary.", .warning)
            log(accessibility.currentAppIdentityDescription(), .warning)
            log("When running from Xcode, macOS may require granting permission to the built app in DerivedData and then relaunching it.", .warning)
            return false
        }

        guard accessibility.findWhatsAppApplication() != nil else {
            log("Cannot inspect WhatsApp because it is not running.", .warning)
            return false
        }

        return true
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
