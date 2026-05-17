import Foundation

struct DeleteMemoryTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "delete_memory",
        description: "Deletes memory entries by key or deletes a memory entry by id.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")]),
                "key": .object(["type": .string("string")])
            ])
        ],
        exampleParameters: [
            .init(name: "key", value: .string("client_identity"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)

        do {
            let deleted: Bool
            if let id = arguments.uuid(for: "id") {
                deleted = try await context.memoriesRepository.delete(id: id)
            } else if let key = arguments.string(for: "key") {
                deleted = try await context.memoriesRepository.delete(key: key)
            } else {
                return .failure(MemoriesRepositoryError.missingParameter("id or key"))
            }

            return .success(.object([
                "ok": .bool(true),
                "deleted": .bool(deleted)
            ]))
        } catch {
            return .failure(error)
        }
    }
}
