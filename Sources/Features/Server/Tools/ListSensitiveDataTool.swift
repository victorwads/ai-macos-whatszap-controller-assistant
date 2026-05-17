import Foundation

struct ListSensitiveDataTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "list_sensitive_data",
        description: "Lists all saved sensitive data entries. Use this to review the full set of known sensitive values, allowed chats, and usage history metadata.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "subjectId": .object(["type": .string("string")]),
                "reason": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")])
            ]),
            "required": .array([.string("subjectId"), .string("reason")])
        ],
        exampleParameters: [
            .init(name: "subjectId", value: .string("22222222-2222-2222-2222-222222222222")),
            .init(name: "reason", value: .string("auditar os dados conhecidos do cliente"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let subjectId = arguments.string(for: "subjectId")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = arguments.string(for: "reason")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, arguments.int(for: "limit") ?? 50)

        do {
            let entries = try await context.sensitiveDataRepository.list(subjectId: subjectId, reason: reason)
            let audits = await context.sensitiveDataRepository.listAudits(limit: limit)
            return .success(.object([
                "entries": .array(entries.map(context.sensitiveDataSummaryJSONValue)),
                "audits": .array(audits.map(context.sensitiveDataAuditJSONValue))
            ]))
        } catch {
            return .failure(error)
        }
    }
}
