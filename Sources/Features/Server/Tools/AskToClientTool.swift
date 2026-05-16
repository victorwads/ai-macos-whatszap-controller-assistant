import Foundation

struct AskToClientTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "ask_to_client",
        description: "Asks the client out loud and waits for a client response.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "prompt": .object(["type": .string("string")]),
                "language": .object(["type": .string("string")]),
                "voiceIdentifier": .object(["type": .string("string")])
            ]),
            "required": .array([.string("prompt")])
        ]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let prompt = arguments.string(for: "prompt") else {
            return .failure(MCPServerError.missingParameter("prompt"))
        }

        let language = arguments.string(for: "language") ?? context.speechLanguage()
        let voiceIdentifier = arguments.string(for: "voiceIdentifier") ?? context.speechVoiceIdentifier()
        let askEvent = await context.clientVoiceEventsRepository.appendAsk(prompt: prompt)
        await context.refreshPendingClientAskCount()

        do {
            try await context.voiceAssistant.speak(
                prompt,
                language: language,
                voiceIdentifier: voiceIdentifier,
                rate: context.speechRate()
            )

            let transcript = try await context.clientVoiceEventsRepository.waitForAnswer(id: askEvent.id)
            await context.refreshPendingClientAskCount()
            return .success(.object([
                "response": .string(transcript)
            ]))
        } catch {
            await context.refreshPendingClientAskCount()
            return .failure(error)
        }
    }
}
