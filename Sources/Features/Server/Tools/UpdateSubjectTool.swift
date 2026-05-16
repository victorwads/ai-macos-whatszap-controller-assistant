import Foundation

struct UpdateSubjectTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "update_subject",
        description: "Updates an operational subject by id. Use to append eventLog entries and to update summary/initialRequest/nextSteps as the work progresses.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string")]),
                "title": .object(["type": .string("string")]),
                "summary": .object(["type": .string("string")]),
                "initialRequest": .object(["type": .string("string")]),
                "details": .object(["type": .string("string")]),
                "status": .object(["type": .string("string")]),
                "priority": .object(["type": .string("number")]),
                "participants": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "nextSteps": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "eventLog": .object(["type": .string("array"), "items": .object(["type": .string("object")])]),
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
            .init(name: "initialRequest", value: .string("Refresh the subject data.")),
            .init(name: "details", value: .string("Expanded with more context.")),
            .init(name: "status", value: .string("active")),
            .init(name: "priority", value: .number(2)),
            .init(name: "participants", value: .array([.string("Codex"), .string("Client")])),
            .init(name: "nextSteps", value: .array([.string("Review")])),
            .init(name: "eventLog", value: .array([])),
            .init(name: "whatsappChatId", value: .string("chat-1")),
            .init(name: "whatsappAfterMessageId", value: .string("m2")),
            .init(name: "gmailThreadId", value: .string("")),
            .init(name: "calendarEventId", value: .string(""))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let id = arguments.uuid(for: "id") else {
            return .failure(SubjectsRepositoryError.invalidParameter("Invalid id"))
        }

        let status = arguments.string(for: "status").flatMap(SubjectStatus.init(rawValue:))
        do {
            let entry = try await context.subjectsRepository.update(
                id: id,
                title: arguments.string(for: "title"),
                summary: arguments.string(for: "summary"),
                initialRequest: arguments.string(for: "initialRequest"),
                details: arguments.string(for: "details"),
                status: status,
                priority: arguments.int(for: "priority"),
                participants: arguments.stringArray(for: "participants"),
                nextSteps: arguments.stringArray(for: "nextSteps"),
                eventLog: context.eventEntries(from: call.arguments["eventLog"]?.arrayValue),
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
