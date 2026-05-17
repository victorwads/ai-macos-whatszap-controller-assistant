import Foundation

struct UpdateSensitiveDataTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "update_sensitive_data",
        description: "Updates an existing sensitive data entry by id or key. Use this to change the label, kind, value, or allowed chats without recreating the record.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")]),
                "key": .object(["type": .string("string")]),
                "label": .object(["type": .string("string")]),
                "kind": .object(["type": .string("string")]),
                "value": .object(["type": .string("string")]),
                "allowedChats": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "subjectId": .object(["type": .string("string")]),
                "reason": .object(["type": .string("string")])
            ])
        ],
        exampleParameters: [
            .init(name: "key", value: .string("client_cpf")),
            .init(name: "allowedChats", value: .array([.string("whatsapp-123"), .string("whatsapp-456")])),
            .init(name: "subjectId", value: .string("22222222-2222-2222-2222-222222222222")),
            .init(name: "reason", value: .string("corrigir o dado sensível salvo anteriormente"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let id = arguments.uuid(for: "id")
        let key = arguments.string(for: "key")
        let subjectId = arguments.string(for: "subjectId")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = arguments.string(for: "reason")?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard id != nil || key != nil else {
            return .failure(SensitiveDataRepositoryError.missingParameter("id or key"))
        }

        do {
            let entry = try await context.sensitiveDataRepository.update(
                id: id,
                key: key,
                label: arguments.string(for: "label"),
                kind: arguments.string(for: "kind"),
                value: arguments.string(for: "value"),
                allowedChats: arguments.stringArray(for: "allowedChats"),
                subjectId: subjectId,
                reason: reason
            )
            let audits = await context.sensitiveDataRepository.listAudits(limit: 20)
            return .success(.object([
                "ok": .bool(true),
                "entry": context.sensitiveDataEntryJSONValue(entry),
                "audits": .array(audits.map(context.sensitiveDataAuditJSONValue))
            ]))
        } catch {
            return .failure(error)
        }
    }
}
