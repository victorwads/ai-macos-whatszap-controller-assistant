import Foundation

struct SearchMemoriesTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "search_memories",
        description: "Searches memories by textual similarity and returns the best matches. Use this when you know a word, phrase, or rough description but not the exact memory key.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")])
            ]),
            "required": .array([.string("query")])
        ],
        exampleParameters: [
            .init(name: "query", value: .string("plano de saúde"))
        ],
        traits: [.readOnly]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let query = arguments.string(for: "query")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, arguments.int(for: "limit") ?? 3)
        let results = await context.memoriesRepository.search(query: query, limit: limit)

        return .success(.object([
            "matches": .array(results.map(context.memorySearchResultJSONValue))
        ]))
    }
}
