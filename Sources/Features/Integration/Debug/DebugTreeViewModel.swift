import AppKit
import Foundation

@MainActor
final class DebugTreeViewModel: ObservableObject {
    @Published var selectedNodePath: [Int]?
    @Published var expandedNodeIds: Set<String> = [""]
    @Published var scrollToNodeId: String?

    @Published var favoriteNameDraft = ""
    @Published var selectedFavoriteName: String?
    @Published var favorites: [String: [Int]] = DebugTreeFavoritesRepository.shared.load()

    func resetForNewSnapshot(focusPath: [Int]) {
        selectedNodePath = focusPath
        expandedNodeIds = [""]
        scrollToNodeId = nodeIdString(focusPath)

        syncFavoriteDraftForSelection()
    }

    func syncFromFocusPath(_ focusPath: [Int]) {
        selectedNodePath = focusPath
        scrollToNodeId = nodeIdString(focusPath)
        syncFavoriteDraftForSelection()
    }

    func handleSelectionChanged(snapshot: WhatsAppSnapshot) {
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
}
