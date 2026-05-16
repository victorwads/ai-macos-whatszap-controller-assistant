import AppKit
import Foundation

@MainActor
final class DebugTreeViewModel: ObservableObject {
    @Published var snapshot: WhatsAppSnapshot?
    @Published var focusPath: [Int] = []
    @Published var selectedNodePath: [Int]?
    @Published var expandedNodeIds: Set<String> = [""]
    @Published var scrollToNodeId: String?

    @Published var favoriteNameDraft = ""
    @Published var selectedFavoriteName: String?
    @Published var favorites: [String: [Int]] = DebugTreeFavoritesRepository.shared.load()

    private let captureService: WhatsAppDebugCaptureService
    private let accessibility: AccessibilityService

    init(captureService: WhatsAppDebugCaptureService, accessibility: AccessibilityService) {
        self.captureService = captureService
        self.accessibility = accessibility
    }

    func captureNewSnapshot() {
        guard let snapshot = captureService.captureSnapshot(maxDepth: 14) else {
            return
        }

        resetForNewSnapshot(snapshot: snapshot)
    }

    func resetForNewSnapshot(snapshot: WhatsAppSnapshot) {
        self.snapshot = snapshot
        focusPath = []
        selectedNodePath = []
        expandedNodeIds = [""]
        scrollToNodeId = nodeIdString([])

        syncFavoriteDraftForSelection()
    }

    func focusHere(_ path: [Int]) {
        focusPath = path
        selectedNodePath = path
        scrollToNodeId = nodeIdString(path)
        syncFavoriteDraftForSelection()
    }

    func handleSelectionChanged() {
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
        DebugTreeFavoritesRepository.shared.save(favorites)
        selectedFavoriteName = name
    }

    func removeFavoriteForSelection() {
        guard let selectedFavoriteName else { return }
        favorites.removeValue(forKey: selectedFavoriteName)
        DebugTreeFavoritesRepository.shared.save(favorites)
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

    func saveCurrentCapture(named name: String) {
        guard let snapshot else { return }
        captureService.saveDebugSnapshot(
            named: name,
            focusPath: focusPath,
            snapshot: snapshot
        )
    }

    func selectedAttributes(at path: [Int]) async throws -> [(String, String)] {
        try await accessibility.readAllAttributes(at: path)
            .map { ($0.key, $0.value) }
    }
}
