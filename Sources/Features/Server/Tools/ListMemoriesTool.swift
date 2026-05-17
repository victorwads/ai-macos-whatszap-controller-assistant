import Foundation

struct ListMemoriesTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "list_memories",
        description: "Lists all saved memory entries.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([:])
        ],
        exampleParameters: [],
        traits: [.readOnly]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let entries = await context.memoriesRepository.list()
        return .success(.object([
            "entries": .array(entries.map(context.memoryEntryJSONValue))
        ]))
    }
}
