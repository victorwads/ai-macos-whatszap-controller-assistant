import Foundation

struct CreateMemoryTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "create_memory",
        description: "Creates a new long-term memory entry keyed by `key`.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "key": .object(["type": .string("string")]),
                "content": .object(["type": .string("string")]),
                "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
            ]),
            "required": .array([.string("key"), .string("content")])
        ],
        exampleParameters: [
            .init(name: "key", value: .string("test_memory_key")),
            .init(name: "content", value: .string("This is a preview memory entry.")),
            .init(name: "tags", value: .array([.string("test"), .string("preview")]))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        do {
            let entry = try await context.memoriesRepository.create(
                key: arguments.string(for: "key"),
                content: arguments.string(for: "content"),
                tags: arguments.stringArray(for: "tags")
            )
            return .success(.object([
                "ok": .bool(true),
                "entry": context.memoryEntryJSONValue(entry)
            ]))
        } catch {
            return .failure(error)
        }
    }
}
