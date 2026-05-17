import Foundation

struct UpdateSubjectTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "update_subject",
        description: """
        Updates an existing operational subject by id.

        Use this tool to change fields and record progress while the subject is still open.

        Rules:
        - `nextSteps` replaces the current array
        - `appendUpdatesLog` appends new updates and ignores exact duplicates
        - `stopCondition` can be refined as the understanding of completion changes
        """,
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")]),
                "title": .object(["type": .string("string")]),
                "summary": .object(["type": .string("string")]),
                "stopCondition": .object(["type": .string("string")]),
                "details": .object(["type": .string("string")]),
                "priority": .object(["type": .string("number")]),
                "participants": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "nextSteps": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "appendUpdatesLog": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "whatsappChatId": .object(["type": .string("string")]),
                "whatsappAfterMessageId": .object(["type": .string("string")]),
                "gmailThreadId": .object(["type": .string("string")]),
                "calendarEventId": .object(["type": .string("string")])
            ]),
            "required": .array([.string("id")])
        ],
        exampleParameters: [
            .init(name: "id", value: .string("22222222-2222-2222-2222-222222222222")),
            .init(name: "title", value: .string("Preview subject updated")),
            .init(name: "summary", value: .string("Updated from the preview browser.")),
            .init(name: "stopCondition", value: .string("The subject shows the revised end condition and the work can be closed when it is met.")),
            .init(name: "details", value: .string("Expanded with more context.")),
            .init(name: "priority", value: .number(2)),
            .init(name: "participants", value: .array([.string("Codex"), .string("Client")])),
            .init(name: "nextSteps", value: .array([.string("Review")])),
            .init(name: "appendUpdatesLog", value: .array([.string("Confirmed the next follow-up action with the client.")])),
            .init(name: "whatsappChatId", value: .string("chat-1")),
            .init(name: "whatsappAfterMessageId", value: .string("m2"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let id = arguments.uuid(for: "id") else {
            return .failure(SubjectsRepositoryError.invalidParameter("Invalid id"))
        }

        do {
            let entry = try await context.subjectsRepository.update(
                id: id,
                title: arguments.string(for: "title"),
                summary: arguments.string(for: "summary"),
                stopCondition: arguments.string(for: "stopCondition"),
                details: arguments.string(for: "details"),
                priority: arguments.int(for: "priority"),
                participants: arguments.stringArray(for: "participants"),
                nextSteps: arguments.stringArray(for: "nextSteps"),
                appendUpdatesLog: arguments.stringArray(for: "appendUpdatesLog"),
                whatsappChatId: arguments.string(for: "whatsappChatId"),
                whatsappAfterMessageId: arguments.string(for: "whatsappAfterMessageId"),
                gmailThreadId: arguments.string(for: "gmailThreadId"),
                calendarEventId: arguments.string(for: "calendarEventId")
            )
            return .success(.object([
                "ok": .bool(true),
                "entry": context.subjectEntryJSONValue(entry)
            ]))
        } catch {
            return .failure(error)
        }
    }
}
