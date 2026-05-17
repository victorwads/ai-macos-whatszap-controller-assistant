import Foundation

struct CreateSubjectTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "create_subject",
        description: """
        Creates a new operational subject.

        Use this to start tracking work that needs follow-up, execution, or closure.

        `initialRequest` captures the trigger and is immutable after creation.
        `stopCondition` captures the observable condition that ends the subject.
        Use `update_subject(...)` to record progress over time and refine the stop condition if needed.
        """,
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "title": .object(["type": .string("string")]),
                "summary": .object(["type": .string("string")]),
                "initialRequest": .object(["type": .string("string")]),
                "stopCondition": .object(["type": .string("string")]),
                "details": .object(["type": .string("string")]),
                "priority": .object(["type": .string("number")]),
                "participants": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "nextSteps": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "whatsappChatId": .object(["type": .string("string")]),
                "gmailThreadId": .object(["type": .string("string")]),
                "calendarEventId": .object(["type": .string("string")])
            ]),
            "required": .array([.string("title"), .string("summary"), .string("initialRequest"), .string("stopCondition")])
        ],
        exampleParameters: [
            .init(name: "title", value: .string("Preview subject")),
            .init(name: "summary", value: .string("Subject created from the tools browser preview.")),
            .init(name: "initialRequest", value: .string("Build the new server tools browser.")),
            .init(name: "stopCondition", value: .string("The browser shows the subject with all core fields and the create/update flow works end to end.")),
            .init(name: "details", value: .string("Optional supporting details for the subject.")),
            .init(name: "priority", value: .number(1)),
            .init(name: "participants", value: .array([.string("Codex")])),
            .init(name: "nextSteps", value: .array([.string("Validate the preview")])),
            .init(name: "whatsappChatId", value: .string("chat-1"))
        ],
        traits: [.writesState]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        do {
            let entry = try await context.subjectsRepository.create(
                title: arguments.string(for: "title"),
                summary: arguments.string(for: "summary"),
                initialRequest: arguments.string(for: "initialRequest"),
                stopCondition: arguments.string(for: "stopCondition"),
                details: arguments.string(for: "details"),
                priority: arguments.int(for: "priority"),
                participants: arguments.stringArray(for: "participants"),
                nextSteps: arguments.stringArray(for: "nextSteps"),
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
