import Foundation

struct DeleteMemoryTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "delete_memory",
        description: "Deletes a memory entry by id.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")])
            ]),
            "required": .array([.string("id")])
        ],
        exampleParameters: [
            .init(name: "id", value: .string("11111111-1111-1111-1111-111111111111"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let id = arguments.uuid(for: "id") else {
            return .failure(MemoriesRepositoryError.invalidParameter("Invalid id"))
        }

        do {
            let deleted = try await context.memoriesRepository.delete(id: id)
            return .success(.object([
                "ok": .bool(true),
                "deleted": .bool(deleted)
            ]))
        } catch {
            return .failure(error)
        }
    }
}
