import Foundation

struct DeleteSubjectTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "delete_subject",
        description: "Deletes a subject by id.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")])
            ]),
            "required": .array([.string("id")])
        ]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let id = arguments.uuid(for: "id") else {
            return .failure(SubjectsRepositoryError.invalidParameter("Invalid id"))
        }

        do {
            let deleted = try await context.subjectsRepository.delete(id: id)
            return .success(.object([
                "ok": .bool(true),
                "deleted": .bool(deleted)
            ]))
        } catch {
            return .failure(error)
        }
    }
}
