import Foundation

struct GetMemoryTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "get_memory",
        description: "Fetches a memory entry by its key.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "key": .object(["type": .string("string")])
            ]),
            "required": .array([.string("key")])
        ]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let rawKey = arguments.string(for: "key")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawKey, !rawKey.isEmpty else {
            return .failure(MemoriesRepositoryError.missingParameter("key"))
        }

        let entries = await context.memoriesRepository.list()
        if let entry = entries.first(where: { $0.key == rawKey }) {
            return .success(.object(["entry": context.memoryEntryJSONValue(entry)]))
        }

        return .success(.object(["error": .string("Memory not found"), "key": .string(rawKey)]))
    }
}
