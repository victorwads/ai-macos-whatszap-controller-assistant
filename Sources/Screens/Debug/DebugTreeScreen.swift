import AppKit
import SwiftUI

private extension RawAXNode {
    var outlineChildren: [RawAXNode]? {
        children.isEmpty ? nil : children
    }
}

struct DebugTreeScreen: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedNodePath: [Int]?
    @State private var expandedNodeIds: Set<String> = [""] // root expanded by default
    @State private var selectedNodePreviewImage: NSImage?
    @State private var selectedNodePreviewError: String?
    @State private var isLoadingSelectedNodePreview = false
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let snapshot = appModel.debugSnapshot {
                let focusedNode = snapshot.rootNode.node(at: appModel.debugNodePath) ?? snapshot.rootNode
                let selectedNode = selectedNode(snapshot: snapshot) ?? focusedNode

                HSplitView {
                    List {
                        treeNode(snapshot.rootNode)
                    }
                    .frame(minWidth: 520)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            nodeSummary(focusedNode, title: "Focused Node")
                            Divider()
                            nodePreviewSection
                            Divider()
                            nodeSummary(selectedNode, title: "Selected Node")
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: appModel.debugNodePath) { _, newValue in
                    selectedNodePath = newValue
                }
                .task(id: snapshot.capturedAt) {
                    selectedNodePath = appModel.debugNodePath
                    expandedNodeIds = [""]
                    selectedNodePreviewImage = nil
                    selectedNodePreviewError = nil
                    isLoadingSelectedNodePreview = false
                    previewTask?.cancel()
                    previewTask = nil
                }
                .onChange(of: selectedNodePath) { _, _ in updateSelectedNodePreview(from: snapshot) }
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
                selectedNodePath = appModel.debugNodePath
            } label: {
                Label("Up", systemImage: "arrow.up")
            }
            .disabled(appModel.debugNodePath.isEmpty)

            Button {
                copyToPasteboard(displayPath(appModel.debugNodePath))
            } label: {
                Label("Copy Focus Path", systemImage: "doc.on.doc")
            }
            .disabled(appModel.debugSnapshot == nil)

            Button {
                guard let selectedNodePath else { return }
                copyToPasteboard(displayPath(selectedNodePath))
            } label: {
                Label("Copy Selected Path", systemImage: "doc.on.doc")
            }
            .disabled(selectedNodePath == nil)

            Spacer()

            Text("focus: \(displayPath(appModel.debugNodePath))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(12)
    }

    private var nodePreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if isLoadingSelectedNodePreview {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Capturing preview…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let selectedNodePreviewImage {
                GeometryReader { proxy in
                    Image(nsImage: selectedNodePreviewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: proxy.size.width, maxHeight: 240, alignment: .leading)
                        .clipped()
                }
                .frame(height: 240)
            } else if let selectedNodePreviewError {
                Text(selectedNodePreviewError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a node with a frame to preview what it represents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Text("path=\(displayPath(node.accessibilityPath))  role=\(node.role ?? "nil")  subrole=\(node.subrole ?? "nil")")
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

    private func treeNode(_ node: RawAXNode) -> AnyView {
        let nodeId = nodeIdString(node.accessibilityPath)
        let isExpanded = Binding(
            get: { expandedNodeIds.contains(nodeId) },
            set: { newValue in
                if newValue {
                    expandedNodeIds.insert(nodeId)
                } else {
                    expandedNodeIds.remove(nodeId)
                }
            }
        )

        if node.children.isEmpty {
            return AnyView(row(node))
        }

        return AnyView(
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children) { child in
                    treeNode(child)
                }
            } label: {
                row(node)
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
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedNodePath = node.accessibilityPath
        }
        .onTapGesture(count: 2) {
            guard !node.children.isEmpty else {
                return
            }
            let nodeId = nodeIdString(node.accessibilityPath)
            if expandedNodeIds.contains(nodeId) {
                expandedNodeIds.remove(nodeId)
            } else {
                expandedNodeIds.insert(nodeId)
            }
        }
        .contextMenu {
            Button("Focus Here") {
                appModel.debugNodePath = node.accessibilityPath
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func selectedNode(snapshot: WhatsAppSnapshot) -> RawAXNode? {
        guard let selectedNodePath else { return nil }
        return snapshot.rootNode.node(at: selectedNodePath)
    }

    private func displayPath(_ path: [Int]) -> String {
        path.isEmpty ? "<root>" : path.map(String.init).joined(separator: ".")
    }

    private func nodeIdString(_ path: [Int]) -> String {
        path.map(String.init).joined(separator: ".")
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

    private func updateSelectedNodePreview(from snapshot: WhatsAppSnapshot) {
        previewTask?.cancel()

        selectedNodePreviewImage = nil
        selectedNodePreviewError = nil
        isLoadingSelectedNodePreview = false

        guard let selectedNodePath else { return }
        guard let node = snapshot.rootNode.node(at: selectedNodePath) else { return }
        guard let frame = node.frame else {
            selectedNodePreviewError = "No frame available for this node."
            return
        }

        isLoadingSelectedNodePreview = true
        let padding: CGFloat = 8
        let region = frame.insetBy(dx: -padding, dy: -padding)

        previewTask = Task.detached(priority: .userInitiated) { [region] in
            let cgImage = CGWindowListCreateImage(region, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
            await MainActor.run {
                guard !Task.isCancelled else { return }
                isLoadingSelectedNodePreview = false
                guard let cgImage else {
                    selectedNodePreviewError = "Could not capture screen preview for this node."
                    return
                }
                selectedNodePreviewImage = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: region.width, height: region.height)
                )
            }
        }
    }
}
