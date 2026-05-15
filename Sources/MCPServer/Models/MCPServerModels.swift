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

struct MCPServerCallEntry: Identifiable, Sendable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let durationMilliseconds: Int

    let requestMethod: String
    let requestPath: String
    let requestHeaders: [String: String]
    let requestBody: Data

    let responseStatusCode: Int
    let responseHeaders: [String: String]
    let responseBody: Data

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        durationMilliseconds: Int,
        requestMethod: String,
        requestPath: String,
        requestHeaders: [String: String],
        requestBody: Data,
        responseStatusCode: Int,
        responseHeaders: [String: String],
        responseBody: Data
    ) {
        self.id = id
        self.timestamp = timestamp
        self.durationMilliseconds = durationMilliseconds
        self.requestMethod = requestMethod
        self.requestPath = requestPath
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseStatusCode = responseStatusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
    }
}

extension MCPServerCallEntry {
    var mcpMethod: String? {
        guard let object = requestBodyJSONObject else { return nil }
        return object["method"] as? String
    }

    var mcpIdDescription: String? {
        guard let object = requestBodyJSONObject else { return nil }
        let id = object["id"]
        switch id {
        case let number as NSNumber:
            return number.stringValue
        case let string as String:
            return string
        default:
            return nil
        }
    }

    var mcpToolName: String? {
        guard mcpMethod == "tools/call" else { return nil }
        guard let params = requestBodyJSONObject?["params"] as? [String: Any] else { return nil }
        return params["name"] as? String
    }

    private var requestBodyJSONObject: [String: Any]? {
        guard !requestBody.isEmpty else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: requestBody) else { return nil }
        return json as? [String: Any]
    }
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
    case sendNotConfirmed(String)
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
        case .sendNotConfirmed(let details):
            return "Message send not confirmed. \(details)"
        case .listenerStartFailed:
            return "Failed to start MCP listener."
        }
    }
}
