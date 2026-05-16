import Foundation

struct GetInstructionsTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "get_instructions",
        description: "Returns the assistant instructions configured in the app.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([:])
        ]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        .success(.object(["instructions": .string(context.assistantInstructions())]))
    }
}
