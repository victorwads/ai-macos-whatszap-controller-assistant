import Foundation

struct CreateMemoryTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "create_memory",
        description: """
        Creates or updates a long-term memory entry keyed by `key`.

        Use this for durable facts and standing instructions that should keep influencing future interactions. If the key already exists, it updates the existing memory instead of creating a duplicate.

        Do not tell the user you will remember something unless you save the memory first.
        """,
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "key": .object(["type": .string("string")]),
                "content": .object(["type": .string("string")])
            ]),
            "required": .array([.string("key"), .string("content")])
        ],
        exampleParameters: [
            .init(name: "key", value: .string("victor_assertive_feedback_rule")),
            .init(name: "content", value: .string("Whenever Victor becomes rude or unnecessarily aggressive, explain calmly how he could have said it in a more assertive and non-violent way."))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        do {
            let result = try await context.memoriesRepository.save(
                key: arguments.string(for: "key"),
                content: arguments.string(for: "content")
            )
            return .success(.object([
                "ok": .bool(true),
                "created": .bool(result.created),
                "updated": .bool(result.updated),
                "entry": context.memoryEntryJSONValue(result.entry)
            ]))
        } catch {
            return .failure(error)
        }
    }
}
