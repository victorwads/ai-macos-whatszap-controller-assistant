import Foundation

struct FinishSubjectTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "finish_subject",
        description: "Marks a subject as finished by id.",
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
            let entry = try await context.subjectsRepository.finish(id: id)
            return .success(.object([
                "ok": .bool(true),
                "entry": context.subjectEntryJSONValue(entry)
            ]))
        } catch {
            return .failure(error)
        }
    }
}
