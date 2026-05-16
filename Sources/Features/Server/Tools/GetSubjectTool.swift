import Foundation

struct GetSubjectTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "get_subject",
        description: "Fetches a subject by id.",
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
        traits: [.readOnly]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let id = arguments.uuid(for: "id") else {
            return .failure(SubjectsRepositoryError.invalidParameter("Invalid id"))
        }

        do {
            let entry = try await context.subjectsRepository.get(id: id)
            return .success(.object(["entry": context.subjectEntryJSONValue(entry)]))
        } catch {
            return .failure(error)
        }
    }
}
