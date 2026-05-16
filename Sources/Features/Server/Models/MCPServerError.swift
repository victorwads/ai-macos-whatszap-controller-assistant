import Foundation

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
