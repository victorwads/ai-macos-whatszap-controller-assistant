import Foundation

struct ListActiveSubjectsTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "list_active_subjects",
        description: "Lists active subjects.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([:])
        ]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let entries = await context.subjectsRepository.listActive()
        return .success(.object([
            "entries": .array(entries.map(context.subjectEntryJSONValue))
        ]))
    }
}
