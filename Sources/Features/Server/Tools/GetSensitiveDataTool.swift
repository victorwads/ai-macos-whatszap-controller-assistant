import Foundation

struct GetSensitiveDataTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "get_sensitive_data",
        description: "Fetches one sensitive data entry by exact key or id. Use this only when you already know the specific record you need and the current chat is authorized to use it.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")]),
                "key": .object(["type": .string("string")]),
                "subjectId": .object(["type": .string("string")]),
                "reason": .object(["type": .string("string")])
            ])
        ],
        exampleParameters: [
            .init(name: "key", value: .string("client_cpf")),
            .init(name: "subjectId", value: .string("22222222-2222-2222-2222-222222222222")),
            .init(name: "reason", value: .string("preencher cadastro no WhatsApp"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let subjectId = arguments.string(for: "subjectId")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = arguments.string(for: "reason")?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let entry: SensitiveDataEntry
            if let id = arguments.uuid(for: "id") {
                entry = try await context.sensitiveDataRepository.get(id: id, subjectId: subjectId, reason: reason)
            } else if let key = arguments.string(for: "key") {
                entry = try await context.sensitiveDataRepository.get(key: key, subjectId: subjectId, reason: reason)
            } else {
                return .failure(SensitiveDataRepositoryError.missingParameter("id or key"))
            }

            let audits = await context.sensitiveDataRepository.listAudits(limit: 20)
            return .success(.object([
                "entry": context.sensitiveDataEntryJSONValue(entry),
                "audits": .array(audits.map(context.sensitiveDataAuditJSONValue))
            ]))
        } catch {
            return .failure(error)
        }
    }
}
