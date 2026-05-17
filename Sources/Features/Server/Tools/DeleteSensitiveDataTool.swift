import Foundation

struct DeleteSensitiveDataTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "delete_sensitive_data",
        description: "Deletes a sensitive data entry by id or key. Use this only when the data is wrong, obsolete, or should no longer be retained.",
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
            .init(name: "reason", value: .string("remover dado sensível incorreto"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let subjectId = arguments.string(for: "subjectId")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = arguments.string(for: "reason")?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let deleted: Bool
            if let id = arguments.uuid(for: "id") {
                deleted = try await context.sensitiveDataRepository.delete(id: id, subjectId: subjectId, reason: reason)
            } else if let key = arguments.string(for: "key") {
                deleted = try await context.sensitiveDataRepository.delete(key: key, subjectId: subjectId, reason: reason)
            } else {
                return .failure(SensitiveDataRepositoryError.missingParameter("id or key"))
            }

            let audits = await context.sensitiveDataRepository.listAudits(limit: 20)
            return .success(.object([
                "ok": .bool(true),
                "deleted": .bool(deleted),
                "audits": .array(audits.map(context.sensitiveDataAuditJSONValue))
            ]))
        } catch {
            return .failure(error)
        }
    }
}
