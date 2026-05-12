import AppKit
import SwiftUI

private extension RawAXNode {
    var outlineChildren: [RawAXNode]? { children.isEmpty ? nil : children }
}

struct DebugTreeScreen: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var model = DebugTreeViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let snapshot = appModel.debugSnapshot {
                let focusedNode = snapshot.rootNode.node(at: appModel.debugNodePath) ?? snapshot.rootNode
                let selectedNode = snapshot.rootNode.node(at: model.selectedNodePath ?? []) ?? focusedNode

                HSplitView {
                    ScrollViewReader { proxy in
                        List(selection: $model.selectedNodePath) {
                            treeNode(snapshot.rootNode)
                        }
                        .frame(minWidth: 520)
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
                            previewSection
                            Divider()
                            favoritesSection
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: appModel.debugNodePath) { _, newValue in
                    model.syncFromFocusPath(newValue)
                }
                .task(id: snapshot.capturedAt) {
                    model.resetForNewSnapshot(focusPath: appModel.debugNodePath)
                }
                .onChange(of: model.selectedNodePath) { _, _ in
                    model.handleSelectionChanged(snapshot: snapshot)
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
                appModel.captureDebugSnapshot()
            } label: {
                Label("Capture", systemImage: "camera")
            }

            Button {
                guard !appModel.debugNodePath.isEmpty else { return }
                appModel.debugNodePath.removeLast()
                model.selectedNodePath = appModel.debugNodePath
            } label: {
                Label("Up", systemImage: "arrow.up")
            }
            .disabled(appModel.debugNodePath.isEmpty)

            Button {
                copyToPasteboard(model.displayPath(appModel.debugNodePath))
            } label: {
                Label("Copy Focus Path", systemImage: "doc.on.doc")
            }
            .disabled(appModel.debugSnapshot == nil)

            Button {
                copyToPasteboard(model.displayPath(model.selectedNodePath ?? []))
            } label: {
                Label("Copy Selected Path", systemImage: "doc.on.doc")
            }
            .disabled(model.selectedNodePath == nil)

            Spacer()

            Text("focus: \(model.displayPath(appModel.debugNodePath))")
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
            Button("Focus Here") { appModel.debugNodePath = node.accessibilityPath }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if model.isLoadingSelectedNodePreview {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Capturing preview…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let image = model.selectedNodePreviewImage {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: proxy.size.width, maxHeight: 240, alignment: .leading)
                        .clipped()
                }
                .frame(height: 240)
            } else if let error = model.selectedNodePreviewError {
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
                            DebugTreeFavoritesStore.save(model.favorites)
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
}
