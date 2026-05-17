import Foundation

struct ListNicknamesTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "list_nicknames",
        description: "Lists saved nicknames. With no arguments it returns every nickname. With a query, it returns matching nicknames by alias or original name, and falls back to the full list when nothing matches.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")])
            ])
        ],
        exampleParameters: [
            .init(name: "query", value: .string("Fred"))
        ],
        traits: [.readOnly]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let lookupTerm = arguments.string(for: "query")?.trimmingCharacters(in: .whitespacesAndNewlines)

        let allNicknames = await context.nicknamesRepository.list()

        guard let lookupTerm, !lookupTerm.isEmpty else {
            return .success(.object([
                "nicknames": .array(allNicknames.map(context.nicknameEntryJSONValue))
            ]))
        }

        let foundNicknames = await context.nicknamesRepository.list(query: lookupTerm)

        if !foundNicknames.isEmpty {
            return .success(.object([
                "foundNicknames": .array(foundNicknames.map(context.nicknameEntryJSONValue))
            ]))
        }

        return .success(.object([
            "message": .string("No nickname matched the provided lookup term. Returning the unfiltered nickname list as fallback."),
            "foundNicknames": .array([]),
            "allNicknames": .array(allNicknames.map(context.nicknameEntryJSONValue))
        ]))
    }
}
