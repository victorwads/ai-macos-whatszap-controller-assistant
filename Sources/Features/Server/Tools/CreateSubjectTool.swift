import Foundation

struct CreateSubjectTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "create_subject",
        description: "Creates a new operational subject to track until resolution.\n\nRequired fields:\n- title: short label\n- summary: detailed operational summary (context + goal + success criteria)\n- initialRequest: triggering request/event (quote or concrete paraphrase)\n\nUse nextSteps for follow-up actions. Use eventLog to record events that happen during the subject's lifecycle (discoveries, outreach, confirmations, calendar updates, client notifications).",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "title": .object(["type": .string("string")]),
                "summary": .object(["type": .string("string")]),
                "initialRequest": .object(["type": .string("string")]),
                "details": .object(["type": .string("string")]),
                "priority": .object(["type": .string("number")]),
                "participants": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "nextSteps": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "eventLog": .object(["type": .string("array"), "items": .object(["type": .string("object")])]),
                "whatsappChatId": .object(["type": .string("string")]),
                "gmailThreadId": .object(["type": .string("string")]),
                "calendarEventId": .object(["type": .string("string")])
            ]),
            "required": .array([.string("title"), .string("summary"), .string("initialRequest")])
        ]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        do {
            let entry = try await context.subjectsRepository.create(
                title: arguments.string(for: "title"),
                summary: arguments.string(for: "summary"),
                initialRequest: arguments.string(for: "initialRequest"),
                details: arguments.string(for: "details"),
                priority: arguments.int(for: "priority"),
                participants: arguments.stringArray(for: "participants"),
                nextSteps: arguments.stringArray(for: "nextSteps"),
                eventLog: context.eventEntries(from: call.arguments["eventLog"]?.arrayValue),
                whatsappChatId: arguments.string(for: "whatsappChatId"),
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
