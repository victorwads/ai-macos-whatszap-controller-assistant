import Foundation

@MainActor
protocol MCPToolHandler {
    static var definition: MCPToolDefinition { get }
    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error>
}
