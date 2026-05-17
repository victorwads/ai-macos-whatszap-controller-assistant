import Foundation

struct SearchSensitiveDataTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "search_sensitive_data",
        description: "Searches sensitive data by textual similarity and returns the best matches. Use this when you know a label, type, or partial detail but not the exact key.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")]),
                "subjectId": .object(["type": .string("string")]),
                "reason": .object(["type": .string("string")])
            ]),
            "required": .array([.string("query"), .string("subjectId"), .string("reason")])
        ],
        exampleParameters: [
            .init(name: "query", value: .string("CPF")),
            .init(name: "subjectId", value: .string("22222222-2222-2222-2222-222222222222")),
            .init(name: "reason", value: .string("encontrar o dado correto para preencher a consulta"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let query = arguments.string(for: "query")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, arguments.int(for: "limit") ?? 3)
        let subjectId = arguments.string(for: "subjectId")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = arguments.string(for: "reason")?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let matches = try await context.sensitiveDataRepository.search(query: query, limit: limit, subjectId: subjectId, reason: reason)
            let audits = await context.sensitiveDataRepository.listAudits(limit: 20)

            return .success(.object([
                "matches": .array(matches.map {
                    .object([
                        "score": .number($0.score),
                        "entry": context.sensitiveDataSummaryJSONValue($0.entry)
                    ])
                    .pruningNulls()
                }),
                "audits": .array(audits.map(context.sensitiveDataAuditJSONValue))
            ]))
        } catch {
            return .failure(error)
        }
    }
}
