import AppKit
import Foundation

@MainActor
final class DebugTreeViewModel: ObservableObject {
    @Published var selectedNodePath: [Int]?
    @Published var expandedNodeIds: Set<String> = [""]
    @Published var selectedNodePreviewImage: NSImage?
    @Published var selectedNodePreviewError: String?
    @Published var isLoadingSelectedNodePreview = false
    @Published var scrollToNodeId: String?

    @Published var favoriteNameDraft = ""
    @Published var selectedFavoriteName: String?
    @Published var favorites: [String: [Int]] = DebugTreeFavoritesStore.load()

    private var previewTask: Task<Void, Never>?
    private var previewCache: [String: NSImage] = [:]
    private var lastPreviewCacheKey: String?

    func resetForNewSnapshot(focusPath: [Int]) {
        selectedNodePath = focusPath
        expandedNodeIds = [""]
        scrollToNodeId = nodeIdString(focusPath)

        selectedNodePreviewImage = nil
        selectedNodePreviewError = nil
        isLoadingSelectedNodePreview = false

        previewTask?.cancel()
        previewTask = nil
        previewCache = [:]
        lastPreviewCacheKey = nil

        syncFavoriteDraftForSelection()
    }

    func syncFromFocusPath(_ focusPath: [Int]) {
        selectedNodePath = focusPath
        scrollToNodeId = nodeIdString(focusPath)
        syncFavoriteDraftForSelection()
    }

    func handleSelectionChanged(snapshot: WhatsAppSnapshot) {
        setPreviewLoadingImmediately(snapshot: snapshot)
        updateSelectedNodePreview(snapshot: snapshot)
        syncFavoriteDraftForSelection()
    }

    func displayPath(_ path: [Int]) -> String {
        path.isEmpty ? "<root>" : path.map(String.init).joined(separator: ".")
    }

    func nodeIdString(_ path: [Int]) -> String {
        path.map(String.init).joined(separator: ".")
    }

    func revealPathInTree(_ path: [Int]) {
        expandedNodeIds.insert("")
        var prefix: [Int] = []
        for index in path {
            prefix.append(index)
            expandedNodeIds.insert(nodeIdString(prefix))
        }
        scrollToNodeId = nodeIdString(path)
    }

    func saveFavoriteForSelection() {
        guard let selectedNodePath else { return }
        let name = favoriteNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        favorites[name] = selectedNodePath
        DebugTreeFavoritesStore.save(favorites)
        selectedFavoriteName = name
    }

    func removeFavoriteForSelection() {
        guard let selectedFavoriteName else { return }
        favorites.removeValue(forKey: selectedFavoriteName)
        DebugTreeFavoritesStore.save(favorites)
        syncFavoriteDraftForSelection()
    }

    func syncFavoriteDraftForSelection() {
        guard let selectedNodePath else {
            selectedFavoriteName = nil
            favoriteNameDraft = ""
            return
        }

        if let existing = favorites.first(where: { $0.value == selectedNodePath })?.key {
            selectedFavoriteName = existing
            favoriteNameDraft = existing
        } else {
            selectedFavoriteName = nil
            favoriteNameDraft = ""
        }
    }

    // MARK: - Preview

    private func cacheKey(snapshot: WhatsAppSnapshot, path: [Int]) -> String {
        "\(snapshot.capturedAt.timeIntervalSinceReferenceDate)|\(nodeIdString(path))"
    }

    private func setPreviewLoadingImmediately(snapshot: WhatsAppSnapshot) {
        guard let selectedNodePath else {
            isLoadingSelectedNodePreview = false
            return
        }

        let key = cacheKey(snapshot: snapshot, path: selectedNodePath)
        if previewCache[key] != nil {
            isLoadingSelectedNodePreview = false
            return
        }

        isLoadingSelectedNodePreview = true
    }

    private func updateSelectedNodePreview(snapshot: WhatsAppSnapshot) {
        previewTask?.cancel()

        selectedNodePreviewImage = nil
        selectedNodePreviewError = nil

        guard let selectedNodePath else {
            isLoadingSelectedNodePreview = false
            return
        }

        guard let node = snapshot.rootNode.node(at: selectedNodePath) else {
            isLoadingSelectedNodePreview = false
            return
        }

        guard let frame = node.frame else {
            selectedNodePreviewError = "No frame available for this node."
            isLoadingSelectedNodePreview = false
            return
        }

        let key = cacheKey(snapshot: snapshot, path: selectedNodePath)
        if lastPreviewCacheKey == key, selectedNodePreviewImage != nil || selectedNodePreviewError != nil {
            isLoadingSelectedNodePreview = false
            return
        }
        lastPreviewCacheKey = key

        if let cached = previewCache[key] {
            selectedNodePreviewImage = cached
            isLoadingSelectedNodePreview = false
            return
        }

        let padding: CGFloat = 8
        let region = frame.insetBy(dx: -padding, dy: -padding)

        previewTask = Task.detached(priority: .userInitiated) { [region] in
            let image = DebugTreePreviewCapture.capture(region: region)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isLoadingSelectedNodePreview = false
                guard let image else {
                    self.selectedNodePreviewError = "Could not capture screen preview for this node."
                    return
                }
                self.selectedNodePreviewImage = image
                self.previewCache[key] = image
            }
        }
    }
}
