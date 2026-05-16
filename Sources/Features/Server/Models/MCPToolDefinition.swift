import Foundation

struct MCPToolDefinition {
    let name: String
    let description: String
    let inputSchema: [String: JSONValue]

    var jsonValue: JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object(inputSchema)
        ])
    }
}
