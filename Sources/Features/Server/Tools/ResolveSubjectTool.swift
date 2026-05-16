import Foundation

struct ResolveSubjectTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "resolve_subject",
        description: "Marks a subject as resolved by id.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")])
            ]),
            "required": .array([.string("id")])
        ],
        exampleParameters: [
            .init(name: "id", value: .string("22222222-2222-2222-2222-222222222222"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let id = arguments.uuid(for: "id") else {
            return .failure(SubjectsRepositoryError.invalidParameter("Invalid id"))
        }

        do {
            let entry = try await context.subjectsRepository.resolve(id: id)
            return .success(.object([
                "ok": .bool(true),
                "entry": context.subjectEntryJSONValue(entry)
            ]))
        } catch {
            return .failure(error)
        }
    }
}
