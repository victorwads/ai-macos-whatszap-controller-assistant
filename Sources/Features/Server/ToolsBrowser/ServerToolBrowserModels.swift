import Combine
import Foundation
import SwiftUI

enum ServerToolGroup: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all = "All"
    case whatsapp = "WhatsApp"
    case voice = "Voice"
    case memories = "Memories"
    case subjects = "Subjects"
    case nicknames = "Nicknames"
    case utilities = "Utilities"

    var id: String { rawValue }
}

enum ServerToolExecutionState: Equatable, Sendable {
    case idle
    case running(String)
    case success
    case failure
}

@MainActor
protocol MCPToolExecutionProviding: AnyObject {
    func executeTool(name: String, arguments: [String: JSONValue]) async -> Result<JSONValue, Error>
}

extension JSONValue {
    func prettyPrintedJSONString() -> String {
        (try? JSONEncoder().encode(self))
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { raw in
                guard
                    let data = raw.data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data),
                    JSONSerialization.isValidJSONObject(object),
                    let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
                    let text = String(data: pretty, encoding: .utf8)
                else {
                    return raw
                }
                return text
            } ?? "{}"
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func prettyPrintedJSONString() -> String {
        JSONValue.object(self).prettyPrintedJSONString()
    }
}

extension MCPToolDefinition {
    var requiredArgumentNames: [String] {
        inputSchema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    var exampleParametersDictionary: [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: exampleParameters.map { ($0.name, $0.value) })
    }

    var exampleParametersJSONText: String {
        exampleParametersDictionary.prettyPrintedJSONString()
    }

    var browserGroup: ServerToolGroup {
        let lowered = name.lowercased()
        if lowered.contains("memory") {
            return .memories
        }
        if lowered.contains("subject") {
            return .subjects
        }
        if lowered.contains("nickname") {
            return .nicknames
        }
        if lowered.contains("voice") || lowered.contains("speak") || lowered.contains("ask") {
            return .voice
        }
        if lowered.contains("chat") || lowered.contains("message") || lowered.contains("wait") {
            return .whatsapp
        }
        return .utilities
    }
}

struct ServerToolBrowserEntry: Identifiable, Sendable {
    let definition: MCPToolDefinition

    var id: String { definition.name }
    var name: String { definition.name }
    var description: String { definition.description }
    var group: ServerToolGroup { definition.browserGroup }
    var traits: [MCPToolTrait] { definition.traits }
    var requiredArgumentNames: [String] { definition.requiredArgumentNames }
    var exampleParameters: [MCPToolExampleParameter] { definition.exampleParameters }
    var exampleParametersDictionary: [String: JSONValue] { definition.exampleParametersDictionary }
    var exampleParametersJSONText: String { definition.exampleParametersJSONText }

    var traitLabels: [String] {
        traits.map(\.displayName)
    }

    var traitColor: Color {
        if traits.contains(.blocking) { return .orange }
        if traits.contains(.sideEffect) { return .red }
        if traits.contains(.writesState) { return .blue }
        return .secondary
    }
}

@MainActor
final class ServerToolBrowserViewModel: ObservableObject {
    @Published var selectedGroup: ServerToolGroup = .all
    @Published var searchQuery = ""
    @Published var selectedToolID: String?
    @Published var executionState: ServerToolExecutionState = .idle
    @Published var resultText = "Select a tool and run a test."
    @Published var resultIsError = false
    @Published var lastRunTimestamp: Date?
    @Published var inputDraftsByToolID: [String: [String: JSONValue]]

    private weak var executor: (any MCPToolExecutionProviding)?
    private var runningTask: Task<Void, Never>?

    let tools: [ServerToolBrowserEntry]

    init(toolDefinitions: [MCPToolDefinition], executor: (any MCPToolExecutionProviding)? = nil, selectedToolID: String? = nil) {
        self.tools = toolDefinitions.map(ServerToolBrowserEntry.init(definition:))
        self.executor = executor
        self.selectedToolID = selectedToolID ?? tools.first?.id
        self.inputDraftsByToolID = Dictionary(
            uniqueKeysWithValues: self.tools.map { tool in
                (tool.id, tool.exampleParametersDictionary)
            }
        )
    }

    deinit {
        runningTask?.cancel()
    }

    var selectedTool: ServerToolBrowserEntry? {
        tools.first(where: { $0.id == selectedToolID })
    }

    func setExecutor(_ executor: (any MCPToolExecutionProviding)?) {
        self.executor = executor
    }

    func currentArguments(for tool: ServerToolBrowserEntry) -> [String: JSONValue] {
        inputDraftsByToolID[tool.id, default: tool.exampleParametersDictionary]
    }

    func currentArgumentsJSONText(for tool: ServerToolBrowserEntry) -> String {
        currentArguments(for: tool).prettyPrintedJSONString()
    }

    var filteredTools: [ServerToolBrowserEntry] {
        tools.filter { tool in
            let groupMatches = selectedGroup == .all || tool.group == selectedGroup
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let searchMatches: Bool

            if query.isEmpty {
                searchMatches = true
            } else {
                searchMatches =
                    tool.name.lowercased().contains(query)
                    || tool.description.lowercased().contains(query)
                    || tool.group.rawValue.lowercased().contains(query)
                    || tool.traitLabels.joined(separator: " ").lowercased().contains(query)
            }

            return groupMatches && searchMatches
        }
    }

    var availableGroups: [ServerToolGroup] {
        let groups = Set(tools.map(\.group))
        return [.all] + ServerToolGroup.allCases.filter { $0 != .all && groups.contains($0) }
    }

    var resultHeaderText: String {
        switch executionState {
        case .idle:
            return "Idle"
        case .running(let name):
            return "Running \(name)"
        case .success:
            return "Completed"
        case .failure:
            return "Failed"
        }
    }

    func bindValue(for toolID: String, argumentName: String) -> Binding<String> {
        Binding(
            get: {
                Self.stringRepresentation(of: self.inputDraftsByToolID[toolID, default: [:]][argumentName])
            },
            set: { newValue in
                var toolDraft = self.inputDraftsByToolID[toolID, default: [:]]
                let existingValue = toolDraft[argumentName]
                toolDraft[argumentName] = Self.parsedJSONValue(from: newValue, existing: existingValue)
                self.inputDraftsByToolID[toolID] = toolDraft
            }
        )
    }

    func selectTool(_ tool: ServerToolBrowserEntry) {
        selectedToolID = tool.id
        resultText = "Select a tool and run a test."
        resultIsError = false
        executionState = .idle
    }

    func runSelectedToolTest() {
        guard let tool = selectedTool else { return }
        guard let executor else {
            resultText = "No MCP executor is attached."
            resultIsError = true
            executionState = .failure
            return
        }

        runningTask?.cancel()
        executionState = .running(tool.name)
        resultText = "Running \(tool.name)..."
        resultIsError = false

        let arguments = currentArguments(for: tool)
        runningTask = Task { [weak self] in
            let result = await executor.executeTool(name: tool.name, arguments: arguments)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                self.lastRunTimestamp = Date()
                switch result {
                case .success(let value):
                    self.executionState = .success
                    self.resultIsError = false
                    self.resultText = value.prettyPrintedJSONString()
                case .failure(let error):
                    self.executionState = .failure
                    self.resultIsError = true
                    self.resultText = error.localizedDescription
                }
            }
        }
    }

    func cancelCurrentRun() {
        runningTask?.cancel()
        runningTask = nil
        executionState = .idle
        resultText = "Run cancelled."
        resultIsError = false
    }

    private static func stringRepresentation(of value: JSONValue?) -> String {
        guard let value else { return "" }

        switch value {
        case .string(let raw):
            return raw
        case .number(let raw):
            return raw.formatted(.number.precision(.fractionLength(0...6)))
        case .bool(let raw):
            return raw ? "true" : "false"
        case .object, .array:
            return value.prettyPrintedJSONString()
        case .null:
            return ""
        }
    }

    private static func parsedJSONValue(from raw: String, existing: JSONValue?) -> JSONValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .null
        }

        if let existing {
            switch existing {
            case .number:
                if let number = Double(trimmed) {
                    return .number(number)
                }
            case .bool:
                let lowered = trimmed.lowercased()
                if lowered == "true" { return .bool(true) }
                if lowered == "false" { return .bool(false) }
            case .array, .object:
                if
                    let data = trimmed.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data),
                    let value = JSONValue.from(any: json)
                {
                    return value
                }
            case .string:
                return .string(raw)
            case .null:
                break
            }
        }

        if
            let data = trimmed.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data),
            let value = JSONValue.from(any: json)
        {
            return value
        }

        return .string(raw)
    }
}

extension ServerToolBrowserViewModel {
    static func preview() -> ServerToolBrowserViewModel {
        ServerToolBrowserViewModel(
            toolDefinitions: MCPServerToolRegistry.toolDefinitions,
            executor: ServerToolPreviewExecutor(),
            selectedToolID: "ask_to_client"
        )
    }
}

@MainActor
final class ServerToolPreviewExecutor: MCPToolExecutionProviding {
    func executeTool(name: String, arguments: [String : JSONValue]) async -> Result<JSONValue, Error> {
        if name.contains("wait") {
            try? await Task.sleep(for: .seconds(1))
            return .failure(MCPServerError.invalidRequest)
        }

        let payload: [String: JSONValue] = [
            "ok": .bool(true),
            "tool": .string(name),
            "arguments": .object(arguments)
        ]
        return .success(.object(payload))
    }
}
