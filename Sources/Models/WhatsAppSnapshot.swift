import Foundation

struct WhatsAppSnapshot {
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let capturedAt: Date
    let rootNode: RawAXNode

    var prettyDescription: String {
        """
        WhatsApp snapshot:
          bundle id: \(bundleIdentifier)
          pid: \(processIdentifier)
          captured at: \(capturedAt.formatted(date: .abbreviated, time: .standard))
        \(rootNode.prettyDescription())
        """
    }
}
