import Foundation

struct WaitNextEventTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "wait_next_event",
        description: "Waits until the next event appears in memory and returns it. Compatibility alias for wait_for_message.",
        inputSchema: WaitForMessageTool.definition.inputSchema,
        exampleParameters: WaitForMessageTool.definition.exampleParameters,
        traits: WaitForMessageTool.definition.traits
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        await WaitForMessageTool.handle(call, context: context)
    }
}
