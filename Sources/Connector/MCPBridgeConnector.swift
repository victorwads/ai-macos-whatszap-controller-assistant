import Foundation
import Network

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value.")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }

        return nil
    }

    var intValue: Int? {
        if case .number(let value) = self {
            return Int(value)
        }

        return nil
    }

    static func from(date: Date?) -> JSONValue {
        guard let date else {
            return .null
        }

        return .string(ISO8601DateFormatter().string(from: date))
    }

    static func from(any value: Any) -> JSONValue? {
        switch value {
        case let value as String:
            return .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.doubleValue)
        case let value as Bool:
            return .bool(value)
        case let value as [String: Any]:
            let object = value.compactMapValues { JSONValue.from(any: $0) }
            return .object(object)
        case let value as [Any]:
            return .array(value.compactMap(JSONValue.from(any:)))
        case _ as NSNull:
            return .null
        default:
            return nil
        }
    }
}

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

private struct IncomingHTTPRequest {
    let method: String
    let path: String
    let body: Data
}

enum MCPBridgeState: Equatable {
    case starting(port: Int)
    case ready(port: Int)
    case failed(message: String)
    case stopped
}

enum MCPBridgeError: LocalizedError {
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

protocol MCPBridgeConnecting: AnyObject {
    var isRunning: Bool { get }
    var boundPort: Int { get }
    func configure(host: String, port: Int)
    func setRequestHandler(_ handler: @escaping @Sendable (MCPHTTPRequest) async -> Result<JSONValue, Error>)
    func setStateHandler(_ handler: @escaping @Sendable (MCPBridgeState) -> Void)
    func start() async throws
    func stop() async
}

final class MCPBridgeConnector: MCPBridgeConnecting {
    private final class StartResolution {
        var hasResolved = false
    }

    private let queue = DispatchQueue(label: "dev.wads.AssistantMCPServer.mcp", qos: .userInitiated)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var listener: NWListener?
    private var handler: (@Sendable (MCPHTTPRequest) async -> Result<JSONValue, Error>)?
    private var stateHandler: (@Sendable (MCPBridgeState) -> Void)?
    private(set) var isRunning = false
    private(set) var boundPort: Int = 8080
    private var host = "localhost"

    func configure(host: String, port: Int) {
        self.host = host
        self.boundPort = port
    }

    func setRequestHandler(_ handler: @escaping @Sendable (MCPHTTPRequest) async -> Result<JSONValue, Error>) {
        self.handler = handler
    }

    func setStateHandler(_ handler: @escaping @Sendable (MCPBridgeState) -> Void) {
        self.stateHandler = handler
    }

    func start() async throws {
        guard listener == nil else {
            return
        }

        guard let port = NWEndpoint.Port(rawValue: UInt16(boundPort)) else {
            throw MCPBridgeError.invalidParameter("port")
        }

        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters, on: port)
        let stateHandler = self.stateHandler
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        self.listener = listener
        stateHandler?(.starting(port: boundPort))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resolution = StartResolution()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    self.isRunning = true
                    stateHandler?(.ready(port: self.boundPort))
                    guard !resolution.hasResolved else { return }
                    resolution.hasResolved = true
                    continuation.resume()
                case .failed(let error):
                    self.isRunning = false
                    self.listener = nil
                    stateHandler?(.failed(message: error.localizedDescription))
                    guard !resolution.hasResolved else { return }
                    resolution.hasResolved = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    self.isRunning = false
                    self.listener = nil
                    stateHandler?(.stopped)
                    guard !resolution.hasResolved else { return }
                    resolution.hasResolved = true
                    continuation.resume(throwing: MCPBridgeError.listenerStartFailed)
                default:
                    break
                }
            }

            listener.start(queue: self.queue)
        }
    }

    func stop() async {
        listener?.cancel()
        listener = nil
        isRunning = false
        stateHandler?(.stopped)
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                let payload = self.httpResponse(status: 500, body: self.errorPayload(message: error.localizedDescription))
                self.respond(on: connection, payload: payload)
                return
            }

            var nextBuffer = buffer
            if let content {
                nextBuffer.append(content)
            }

            if let request = self.parseHTTPRequest(from: nextBuffer) {
                Task {
                    let response = await self.process(request: request)
                    self.respond(on: connection, payload: response)
                }
                return
            }

            if isComplete {
                let payload = self.httpResponse(status: 400, body: self.errorPayload(message: MCPBridgeError.invalidRequest.localizedDescription))
                self.respond(on: connection, payload: payload)
                return
            }

            self.receiveRequest(on: connection, buffer: nextBuffer)
        }
    }

    private func process(request: IncomingHTTPRequest) async -> Data {
        switch request.method {
        case "GET":
            guard request.path == "/mcp" else {
                return httpResponse(status: 404, body: errorPayload(message: "Route not found."))
            }
            return httpResponse(status: 200, body: healthPayload())
        case "POST":
            guard request.path == "/mcp" else {
                return httpResponse(status: 404, body: errorPayload(message: "Route not found."))
            }
        default:
            return httpResponse(status: 405, body: errorPayload(message: "Use POST /mcp for JSON-RPC requests."))
        }

        do {
            let request = try decodeRequest(from: request.body)
            guard let handler else {
                return httpResponse(status: 503, body: errorPayload(message: "MCP handler not configured."))
            }

            let result = await handler(request)
            switch result {
            case .success(let value):
                return httpResponse(status: 200, body: successPayload(id: request.id, result: value))
            case .failure(let error):
                return httpResponse(status: 400, body: errorPayload(id: request.id, message: error.localizedDescription))
            }
        } catch {
            return httpResponse(status: 400, body: errorPayload(message: error.localizedDescription))
        }
    }

    private func decodeRequest(from body: Data) throws -> MCPHTTPRequest {
        guard
            let payloadObject = try JSONSerialization.jsonObject(with: body) as? [String: Any],
            let method = payloadObject["method"] as? String
        else {
            throw MCPBridgeError.invalidRequest
        }

        let id = payloadObject["id"].flatMap(JSONValue.from(any:))
        let params: [String: JSONValue]
        if let paramsObject = payloadObject["params"] as? [String: Any] {
            params = paramsObject.compactMapValues { JSONValue.from(any: $0) }
        } else {
            params = [:]
        }

        return MCPHTTPRequest(id: id, method: method, params: params)
    }

    private func parseHTTPRequest(from data: Data) -> IncomingHTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard
            let headerRange = data.range(of: separator),
            let headers = String(data: data.subdata(in: data.startIndex..<headerRange.lowerBound), encoding: .utf8)
        else {
            return nil
        }

        let headerLines = headers.components(separatedBy: "\r\n")
        guard
            let requestLine = headerLines.first,
            !requestLine.isEmpty
        else {
            return nil
        }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else {
            return nil
        }

        let method = String(requestParts[0]).uppercased()
        let path = String(requestParts[1])
        let bodyStart = headerRange.upperBound
        let contentLength = headerLines
            .first(where: { $0.lowercased().hasPrefix("content-length:") })
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") }
            ?? 0

        guard data.count >= bodyStart + contentLength else {
            return nil
        }

        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return IncomingHTTPRequest(method: method, path: path, body: body)
    }

    private func respond(on connection: NWConnection, payload: Data) {
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func successPayload(id: JSONValue?, result: JSONValue) -> Data {
        let payload: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": id ?? .null,
            "result": result
        ])

        return (try? encoder.encode(payload)) ?? Data()
    }

    private func errorPayload(id: JSONValue? = nil, message: String) -> Data {
        let payload: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": id ?? .null,
            "error": .object([
                "message": .string(message)
            ])
        ])

        return (try? encoder.encode(payload)) ?? Data()
    }

    private func healthPayload() -> Data {
        let payload: JSONValue = .object([
            "ok": .bool(true),
            "service": .string("AssistantMCPServer MCP bridge"),
            "transport": .string("HTTP JSON-RPC"),
            "endpoint": .string("http://\(host):\(boundPort)/mcp"),
            "message": .string("Use POST /mcp with JSON-RPC. Browser GET is only a health check."),
            "supportedMethods": .array([
                .string("initialize"),
                .string("ping"),
                .string("tools/list"),
                .string("tools/call")
            ])
        ])

        return (try? encoder.encode(payload)) ?? Data()
    }

    private func httpResponse(status: Int, body: Data) -> Data {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 503: statusText = "Service Unavailable"
        default: statusText = "Internal Server Error"
        }

        var response = "HTTP/1.1 \(status) \(statusText)\r\n"
        response += "Host: \(host)\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n\r\n"

        return Data(response.utf8) + body
    }
}
