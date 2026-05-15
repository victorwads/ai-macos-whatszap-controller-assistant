import AppKit
import Foundation

@MainActor
final class DebugTreePreviewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var error: String?
    @Published var isLoading = false

    private var previewTask: Task<Void, Never>?
    private var previewCache: [String: NSImage] = [:]
    private var lastCacheKey: String?

    func reset() {
        image = nil
        error = nil
        isLoading = false
        previewTask?.cancel()
        previewTask = nil
        previewCache = [:]
        lastCacheKey = nil
    }

    func setLoadingImmediatelyIfNeeded(snapshot: WhatsAppSnapshot, path: [Int]?) {
        guard let path else {
            isLoading = false
            return
        }

        let key = cacheKey(snapshot: snapshot, path: path)
        if previewCache[key] != nil {
            isLoading = false
            return
        }

        isLoading = true
    }

    func update(snapshot: WhatsAppSnapshot, path: [Int]?) {
        previewTask?.cancel()
        image = nil
        error = nil

        guard let path else {
            isLoading = false
            return
        }

        guard let node = snapshot.rootNode.node(at: path) else {
            isLoading = false
            return
        }

        guard let frame = node.frame else {
            error = "No frame available for this node."
            isLoading = false
            return
        }

        let key = cacheKey(snapshot: snapshot, path: path)
        if lastCacheKey == key, image != nil || error != nil {
            isLoading = false
            return
        }
        lastCacheKey = key

        if let cached = previewCache[key] {
            image = cached
            isLoading = false
            return
        }

        let padding: CGFloat = 8
        let region = frame.insetBy(dx: -padding, dy: -padding)

        previewTask = Task.detached(priority: .userInitiated) { [region] in
            let image = DebugTreePreviewCapture.capture(region: region)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isLoading = false
                guard let image else {
                    self.error = "Could not capture screen preview for this node."
                    return
                }
                self.image = image
                self.previewCache[key] = image
            }
        }
    }

    private func cacheKey(snapshot: WhatsAppSnapshot, path: [Int]) -> String {
        "\(snapshot.capturedAt.timeIntervalSinceReferenceDate)|\(path.map(String.init).joined(separator: "."))"
    }
}

