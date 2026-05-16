import Foundation

enum MCPToolTrait: String, Hashable, Sendable {
    case readOnly = "read-only"
    case writesState = "write-state"
    case sideEffect = "side-effect"
    case blocking = "blocking"

    var displayName: String {
        switch self {
        case .readOnly:
            return "read-only"
        case .writesState:
            return "write-state"
        case .sideEffect:
            return "side-effect"
        case .blocking:
            return "blocking"
        }
    }
}

struct MCPToolExampleParameter: Hashable, Sendable {
    let name: String
    let value: JSONValue

    var jsonValue: JSONValue {
        .object([
            "name": .string(name),
            "value": value
        ])
    }
}

struct MCPToolDefinition {
    let name: String
    let description: String
    let inputSchema: [String: JSONValue]
    let exampleParameters: [MCPToolExampleParameter]
    let traits: [MCPToolTrait]

    var jsonValue: JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object(inputSchema),
            "exampleParameters": .array(exampleParameters.map(\.jsonValue)),
            "traits": .array(traits.map { .string($0.rawValue) })
        ])
    }
}
