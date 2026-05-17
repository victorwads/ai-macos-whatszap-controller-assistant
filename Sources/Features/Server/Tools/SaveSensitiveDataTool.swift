import Foundation

struct SaveSensitiveDataTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "save_sensitive_data",
        description: "Creates or updates a sensitive data entry keyed by `key`. Use this for durable sensitive values such as CPF, birth date, health plan details, or other user data that may be reused later.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "key": .object(["type": .string("string")]),
                "label": .object(["type": .string("string")]),
                "kind": .object(["type": .string("string")]),
                "value": .object(["type": .string("string")]),
                "allowedChats": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "subjectId": .object(["type": .string("string")]),
                "reason": .object(["type": .string("string")])
            ]),
            "required": .array([.string("key"), .string("label"), .string("kind"), .string("value"), .string("subjectId"), .string("reason")])
        ],
        exampleParameters: [
            .init(name: "key", value: .string("client_cpf")),
            .init(name: "label", value: .string("CPF do cliente")),
            .init(name: "kind", value: .string("cpf")),
            .init(name: "value", value: .string("123.456.789-00")),
            .init(name: "allowedChats", value: .array([.string("whatsapp-123")])),
            .init(name: "subjectId", value: .string("22222222-2222-2222-2222-222222222222")),
            .init(name: "reason", value: .string("cadastrar um dado sensível recebido do cliente"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        let subjectId = arguments.string(for: "subjectId")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = arguments.string(for: "reason")?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let result = try await context.sensitiveDataRepository.save(
                key: arguments.string(for: "key"),
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
                "created": .bool(result.created),
                "updated": .bool(result.updated),
                "entry": context.sensitiveDataEntryJSONValue(result.entry),
                "audits": .array(audits.map(context.sensitiveDataAuditJSONValue))
            ]))
        } catch {
            return .failure(error)
        }
    }
}
