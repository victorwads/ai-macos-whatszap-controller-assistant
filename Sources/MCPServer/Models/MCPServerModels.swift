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

struct MCPToolCall {
    let name: String
    let arguments: [String: JSONValue]
}

struct MCPHTTPRequest {
    let id: JSONValue?
    let method: String
    let params: [String: JSONValue]
}

struct IncomingHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

enum MCPServerState: Equatable {
    case starting(port: Int)
    case ready(port: Int)
    case failed(message: String)
    case stopped
}

enum MCPServerError: LocalizedError {
    case invalidRequest
    case unsupportedMethod(String)
    case missingParameter(String)
    case invalidParameter(String)
    case listenerStartFailed

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid JSON-RPC request."
        case .unsupportedMethod(let method):
            return "Unsupported MCP method: \(method)"
        case .missingParameter(let name):
            return "Missing parameter: \(name)"
        case .invalidParameter(let name):
            return "Invalid parameter: \(name)"
        case .listenerStartFailed:
            return "Failed to start MCP listener."
        }
    }
}
