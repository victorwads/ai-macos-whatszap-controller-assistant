import Foundation

struct SpeakToClientTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "speak_to_client",
        description: "Speaks a message out loud to the client using text-to-speech.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "text": .object(["type": .string("string")]),
                "language": .object(["type": .string("string")]),
                "voiceIdentifier": .object(["type": .string("string")]),
                "rate": .object(["type": .string("number")])
            ]),
            "required": .array([.string("text")])
        ],
        exampleParameters: [
            .init(name: "text", value: .string("Testing speak_to_client from the tools browser.")),
            .init(name: "language", value: .string("en-US")),
            .init(name: "voiceIdentifier", value: .string("")),
            .init(name: "rate", value: .number(0.5))
        ],
        traits: [.sideEffect]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let text = arguments.string(for: "text") else {
            return .failure(MCPServerError.missingParameter("text"))
        }

        let language = arguments.string(for: "language") ?? context.speechLanguage()
        let voiceIdentifier = arguments.string(for: "voiceIdentifier") ?? context.speechVoiceIdentifier()
        let rate = arguments.number(for: "rate").map(Float.init) ?? context.speechRate()
        _ = await context.clientVoiceEventsRepository.appendSpeak(text: text)
        await context.refreshPendingClientAskCount()

        do {
            try await context.voiceAssistant.speak(text, language: language, voiceIdentifier: voiceIdentifier, rate: rate)
            return .success(.object(["ok": .bool(true)]))
        } catch {
            return .failure(error)
        }
    }
}
