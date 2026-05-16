import Foundation

struct ListMemoriesByTagTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "list_memories_by_tag",
        description: "Lists memory entries filtered by a specific tag, or all memories when tag is omitted.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "tag": .object(["type": .string("string")])
            ])
        ],
        exampleParameters: [
            .init(name: "tag", value: .string("test"))
        ],
        traits: [.readOnly]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let tag = arguments.string(for: "tag")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = await context.memoriesRepository.list()
        let filtered: [MemoryEntry]
        if let tag, !tag.isEmpty {
            filtered = entries.filter { $0.tags.contains(tag) }
        } else {
            filtered = entries
        }
        return .success(.object(["entries": .array(filtered.map(context.memoryEntryJSONValue))]))
    }
}
