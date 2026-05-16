import SwiftUI

struct ServerToolsScreen: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var viewModel: ServerToolBrowserViewModel

    init(viewModel: ServerToolBrowserViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ServerToolBrowserViewModel(toolDefinitions: MCPServerToolRegistry.toolDefinitions))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBanner
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color(nsColor: .underPageBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Divider()

            HSplitView {
                sidebar
                    .frame(minWidth: 320, idealWidth: 370, maxWidth: 460)

                detailPane
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.setExecutor(appModel.mcpServerCoordinator)
        }
    }

    private var topBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server Tools")
                        .font(.largeTitle.weight(.semibold))

                    Text("Automatic browser for the live MCP registry and real handler execution.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusPill
            }

            HStack(spacing: 8) {
                Label("Mirrors MCPServerToolRegistry", systemImage: "externaldrive.connected.to.line.below")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())

                Label("Traits: read-only, write-state, side-effect, blocking", systemImage: "tag")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())

                if let lastRunTimestamp = viewModel.lastRunTimestamp {
                    Text("Last run: \(lastRunTimestamp, format: .dateTime.hour().minute().second())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No test has been run yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusPill: some View {
        let color: Color
        switch viewModel.executionState {
        case .idle:
            color = .secondary
        case .running:
            color = .blue
        case .success:
            color = .green
        case .failure:
            color = .red
        }

        return Text(viewModel.resultHeaderText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarFilters
                .padding(12)
                .background(.bar)

            Divider()

            List(selection: $viewModel.selectedToolID) {
                ForEach(viewModel.filteredTools) { tool in
                ServerToolRow(tool: tool, isSelected: viewModel.selectedToolID == tool.id)
                        .tag(tool.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectTool(tool)
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sidebarFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search tools", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.availableGroups) { group in
                        Button {
                            viewModel.selectedGroup = group
                        } label: {
                            Text(group.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(viewModel.selectedGroup == group ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var detailPane: some View {
        Group {
            if let selectedTool = viewModel.selectedTool {
                ServerToolDetailPane(
                    tool: selectedTool,
                    state: viewModel.executionState,
                    resultText: viewModel.resultText,
                    resultIsError: viewModel.resultIsError,
                    previewPayloadText: viewModel.currentArgumentsJSONText(for: selectedTool),
                    onRun: { viewModel.runSelectedToolTest() },
                    onCancel: { viewModel.cancelCurrentRun() },
                    argumentBinding: { key in
                        viewModel.bindValue(for: selectedTool.id, argumentName: key)
                    }
                )
            } else {
                ContentUnavailableView(
                    "No tool selected",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Pick a tool from the live registry to inspect its example parameters and run its handler.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

private struct ServerToolRow: View {
    let tool: ServerToolBrowserEntry
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(tool.name)
                    .font(.headline)

                Spacer()

                traitBadges
            }

            Text(tool.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(tool.group.rawValue)
                Text("•")
                Text("\(tool.exampleParameters.count) args")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 4)
    }

    private var traitBadges: some View {
        HStack(spacing: 6) {
            ForEach(tool.traits, id: \.self) { trait in
                Text(trait.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tool.traitColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tool.traitColor.opacity(0.12), in: Capsule())
            }
        }
    }
}

private struct ServerToolDetailPane: View {
    let tool: ServerToolBrowserEntry
    let state: ServerToolExecutionState
    let resultText: String
    let resultIsError: Bool
    let previewPayloadText: String
    let onRun: () -> Void
    let onCancel: () -> Void
    let argumentBinding: (String) -> Binding<String>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                schemaCard
                argumentsCard
                resultCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tool.name)
                        .font(.title2.weight(.semibold))

                    Text(tool.description)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text(tool.group.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())

                    HStack(spacing: 6) {
                        ForEach(tool.traits, id: \.self) { trait in
                            Text(trait.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tool.traitColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(tool.traitColor.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    onRun()
                } label: {
                    Label("Run test", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                if case .running = state {
                    Button {
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Required: \(tool.requiredArgumentNames.isEmpty ? "none" : tool.requiredArgumentNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Example params: \(tool.exampleParameters.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var schemaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Definition")
                .font(.headline)

            SelectableTextBlock(text: tool.definition.jsonValue.prettyPrintedJSONString())
                .frame(minHeight: 160)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var argumentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Example parameters")
                .font(.headline)

            if tool.exampleParameters.isEmpty {
                Text("This tool has no example parameters.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(tool.exampleParameters, id: \.name) { argument in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(argument.name)
                                .font(.subheadline.weight(.semibold))

                            TextField("Enter value", text: argumentBinding(argument.name))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Generated payload")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SelectableTextBlock(text: previewPayloadText)
                    .frame(minHeight: 120)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Result")
                .font(.headline)

            if resultText.isEmpty {
                Text("No result yet.")
                    .foregroundStyle(.secondary)
            } else {
                SelectableTextBlock(text: resultText, isError: resultIsError)
                    .frame(minHeight: 180)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct SelectableTextBlock: View {
    let text: String
    var isError: Bool = false

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isError ? .red : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15))
        )
    }
}

#Preview("Server tools browser") {
    ServerToolsScreen(viewModel: ServerToolBrowserViewModel.preview())
        .environmentObject(AppModel.preview)
        .frame(width: 1280, height: 820)
}

#Preview("Server tools browser - compact") {
    let model = ServerToolBrowserViewModel.preview()
    model.searchQuery = "subject"
    model.selectedGroup = .subjects

    return ServerToolsScreen(viewModel: model)
        .environmentObject(AppModel.preview)
        .frame(width: 1024, height: 720)
}
