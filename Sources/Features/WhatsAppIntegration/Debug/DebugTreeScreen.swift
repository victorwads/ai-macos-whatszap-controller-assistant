import AppKit
import SwiftUI

private extension RawAXNode {
    var outlineChildren: [RawAXNode]? { children.isEmpty ? nil : children }
}

struct DebugTreeScreen: View {
    private let accessibility: AccessibilityService
    @StateObject private var model: DebugTreeViewModel
    @StateObject private var previewModel = DebugTreePreviewModel()
    @State private var attributeQuery = ""
    @State private var captureNameDraft = ""
    @State private var selectedAttributes: [(key: String, value: String)] = []
    @State private var selectedAttributesError: String?
    @State private var isLoadingAttributes = false

    init(captureService: WhatsAppDebugCaptureService, accessibility: AccessibilityService) {
        self.accessibility = accessibility
        _model = StateObject(wrappedValue: DebugTreeViewModel(captureService: captureService, accessibility: accessibility))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let snapshot = model.snapshot {
                let focusedNode = snapshot.rootNode.node(at: model.focusPath) ?? snapshot.rootNode
                let selectedPath = model.selectedNodePath ?? model.focusPath
                let selectedNode = snapshot.rootNode.node(at: selectedPath) ?? focusedNode

                HSplitView {
                    ScrollViewReader { proxy in
                        List(selection: $model.selectedNodePath) {
                            treeNode(snapshot.rootNode)
                        }
                        .frame(minWidth: 320, idealWidth: 520, maxWidth: .infinity)
                        .onChange(of: model.scrollToNodeId) { _, newValue in
                            guard let newValue else { return }
                            withAnimation(.snappy) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            nodeSummary(focusedNode, title: "Focused Node")
                            Divider()
                            nodeSummary(selectedNode, title: "Selected Node")
                            Divider()
                            attributesSection(path: selectedPath)
                            Divider()
                            previewSection
                            Divider()
                            favoritesSection
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 320, maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: snapshot.capturedAt) {
                    model.resetForNewSnapshot(snapshot: snapshot)
                    previewModel.reset()
                    loadAttributes(for: model.selectedNodePath ?? model.focusPath)
                }
                .onChange(of: model.selectedNodePath) { _, _ in
                    model.handleSelectionChanged()
                    previewModel.setLoadingImmediatelyIfNeeded(snapshot: snapshot, path: model.selectedNodePath)
                    previewModel.update(snapshot: snapshot, path: model.selectedNodePath)
                    loadAttributes(for: model.selectedNodePath ?? model.focusPath)
                }
                .task(id: model.nodeIdString(model.selectedNodePath ?? model.focusPath)) {
                    loadAttributes(for: model.selectedNodePath ?? model.focusPath)
                }
            } else {
                ContentUnavailableView(
                    "No snapshot loaded",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Press Capture to load the current WhatsApp accessibility tree.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                model.captureNewSnapshot()
            } label: {
                Label("Capture", systemImage: "camera")
            }

            Button {
                guard !model.focusPath.isEmpty else { return }
                model.focusPath.removeLast()
                model.selectedNodePath = model.focusPath
                model.scrollToNodeId = model.nodeIdString(model.focusPath)
            } label: {
                Label("Up", systemImage: "arrow.up")
            }
            .disabled(model.focusPath.isEmpty)

            Button {
                copyToPasteboard(model.displayPath(model.focusPath))
            } label: {
                Label("Copy Focus Path", systemImage: "doc.on.doc")
            }
            .disabled(model.snapshot == nil)

            Button {
                copyToPasteboard(model.displayPath(model.selectedNodePath ?? []))
            } label: {
                Label("Copy Selected Path", systemImage: "doc.on.doc")
            }
            .disabled(model.selectedNodePath == nil)

            TextField("Capture name", text: $captureNameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            Button {
                model.saveCurrentCapture(named: captureNameDraft)
            } label: {
                Label("Save Capture", systemImage: "square.and.arrow.down")
            }
            .disabled(model.snapshot == nil)

            Spacer()

            Text("focus: \(model.displayPath(model.focusPath))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(12)
    }

    private func treeNode(_ node: RawAXNode) -> AnyView {
        let nodeId = model.nodeIdString(node.accessibilityPath)
        let isExpanded = Binding(
            get: { model.expandedNodeIds.contains(nodeId) },
            set: { newValue in
                if newValue { model.expandedNodeIds.insert(nodeId) }
                else { model.expandedNodeIds.remove(nodeId) }
            }
        )

        if node.children.isEmpty {
            return AnyView(row(node).tag(node.accessibilityPath).id(nodeId))
        }

        return AnyView(
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children) { child in
                    treeNode(child)
                }
            } label: {
                row(node)
                    .tag(node.accessibilityPath)
                    .id(nodeId)
            }
        )
    }

    private func row(_ node: RawAXNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rowTitle(for: node))
                .font(.system(.caption, design: .monospaced))
            Text(rowSubtitle(for: node))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedNodePath = node.accessibilityPath }
        .onTapGesture(count: 2) {
            guard !node.children.isEmpty else { return }
            let nodeId = model.nodeIdString(node.accessibilityPath)
            if model.expandedNodeIds.contains(nodeId) { model.expandedNodeIds.remove(nodeId) }
            else { model.expandedNodeIds.insert(nodeId) }
        }
        .contextMenu {
            Button("Focus Here") { model.focusHere(node.accessibilityPath) }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if previewModel.isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Capturing preview…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let image = previewModel.image {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: proxy.size.width, maxHeight: 240, alignment: .leading)
                        .clipped()
                }
                .frame(height: 240)
            } else if let error = previewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a node with a frame to preview what it represents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Favorite name", text: $model.favoriteNameDraft)
                    .textFieldStyle(.roundedBorder)

                Button("Save") { model.saveFavoriteForSelection() }
                    .disabled(model.selectedNodePath == nil || model.favoriteNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Unsave") { model.removeFavoriteForSelection() }
                    .disabled(model.selectedFavoriteName == nil)
            }

            if let name = model.selectedFavoriteName {
                Text("Saved as: \(name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorites")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if model.favorites.isEmpty {
                Text("No favorites yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.favorites.keys.sorted(), id: \.self) { name in
                    let path = model.favorites[name] ?? []
                    Button {
                        model.revealPathInTree(path)
                        model.selectedNodePath = path
                    } label: {
                        HStack {
                            Text(name)
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text(model.displayPath(path))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove") {
                            model.favorites.removeValue(forKey: name)
                            DebugTreeFavoritesRepository.shared.save(model.favorites)
                            model.syncFavoriteDraftForSelection()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nodeSummary(_ node: RawAXNode, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("path=\(model.displayPath(node.accessibilityPath))  role=\(node.role ?? "nil")  subrole=\(node.subrole ?? "nil")")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            let text = node.ownTextFragments
                .map(debugDisplayText)
                .filter { !$0.isEmpty }
                .joined(separator: " | ")

            if !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            if let frame = node.frame {
                Text("frame x:\(Int(frame.minX)) y:\(Int(frame.minY)) w:\(Int(frame.width)) h:\(Int(frame.height))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowTitle(for node: RawAXNode) -> String {
        let prefix = node.accessibilityPath.last.map(String.init) ?? "root"
        return "\(prefix)  \(node.role ?? "nil")"
    }

    private func rowSubtitle(for node: RawAXNode) -> String {
        let text = node.ownTextFragments
            .map(debugDisplayText)
            .filter { !$0.isEmpty }
            .prefix(3)
            .joined(separator: " | ")
        return text.isEmpty ? "—" : text
    }

    private func debugDisplayText(_ text: String) -> String {
        text.normalizedAXText
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func loadAttributes(for path: [Int]) {
        isLoadingAttributes = true
        selectedAttributesError = nil

        Task { @MainActor in
            do {
                let attributes = try await model.selectedAttributes(at: path)
                selectedAttributes = attributes
                    .map { ($0.0, $0.1) }
                    .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
            } catch {
                selectedAttributes = []
                selectedAttributesError = error.localizedDescription
            }

            isLoadingAttributes = false
        }
    }

    private func attributesSection(path: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Attributes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Text(model.displayPath(path))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                TextField("Filter attributes (name/value)", text: $attributeQuery)
                    .textFieldStyle(.roundedBorder)

                if isLoadingAttributes {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let selectedAttributesError {
                Text(selectedAttributesError)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
            } else if selectedAttributes.isEmpty {
                Text("No attributes found.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                let filtered = filteredAttributes()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(filtered, id: \.key) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Text(row.key)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .frame(width: 220, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text(row.value)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filteredAttributes() -> [(key: String, value: String)] {
        let trimmed = attributeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return selectedAttributes }

        let needle = trimmed.lowercased()
        return selectedAttributes.filter { row in
            row.key.lowercased().contains(needle) || row.value.lowercased().contains(needle)
        }
    }
}

#Preview {
    let appModel = AppModel.preview
    DebugTreeScreen(captureService: appModel.whatsAppDebugService, accessibility: appModel.accessibility)
        .frame(width: 1100, height: 720)
}
