import Foundation

struct GetMemoryTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "get_memory",
        description: "Fetches one saved memory by its exact `key`. Use this only when you already know the key you want.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "key": .object(["type": .string("string")])
            ]),
            "required": .array([.string("key")])
        ],
        exampleParameters: [
            .init(name: "key", value: .string("client_identity"))
        ],
        traits: [.readOnly]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let rawKey = arguments.string(for: "key")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawKey, !rawKey.isEmpty else {
            return .failure(MemoriesRepositoryError.missingParameter("key"))
        }

        do {
            let entry = try await context.memoriesRepository.get(key: rawKey)
            return .success(.object(["entry": context.memoryEntryJSONValue(entry)]))
        } catch {
            return .success(.object(["error": .string("Memory not found"), "key": .string(rawKey)]))
        }
    }
}
