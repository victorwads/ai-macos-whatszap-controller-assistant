import Foundation
import Network

final class MCPHTTPServer: MCPServerTransporting {
    private final class StartResolution {
        var hasResolved = false
    }

    private let queue = DispatchQueue(label: "dev.wads.AssistantMCPServer.mcp", qos: .userInitiated)
    private let encoder = JSONEncoder()

    private var listener: NWListener?
    private var handler: (@Sendable (MCPHTTPRequest) async -> Result<JSONValue, Error>)?
    private var stateHandler: (@Sendable (MCPServerState) -> Void)?
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

    func setStateHandler(_ handler: @escaping @Sendable (MCPServerState) -> Void) {
        self.stateHandler = handler
    }

    func start() async throws {
        guard listener == nil else {
            return
        }

        guard let port = NWEndpoint.Port(rawValue: UInt16(boundPort)) else {
            throw MCPServerError.invalidParameter("port")
        }

        let listener = try NWListener(using: .tcp, on: port)
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
                    continuation.resume(throwing: MCPServerError.listenerStartFailed)
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
                let payload = self.httpResponse(status: 400, body: self.errorPayload(message: MCPServerError.invalidRequest.localizedDescription))
                self.respond(on: connection, payload: payload)
                return
            }

            self.receiveRequest(on: connection, buffer: nextBuffer)
        }
    }

    private func process(request: IncomingHTTPRequest) async -> Data {
        if let origin = request.headers["origin"], !origin.isEmpty, !isAllowedOrigin(origin) {
            return httpResponse(status: 403, body: Data("Forbidden origin.".utf8), contentType: "text/plain; charset=utf-8")
        }

        switch request.method {
        case "GET":
            switch request.path {
            case "/health":
                return httpResponse(status: 200, body: healthPayload())
            case "/mcp":
                // Streamable HTTP transport allows GET only for optional SSE.
                // If SSE is not supported, return 405 per spec.
                return httpResponse(
                    status: 405,
                    body: Data("Method Not Allowed. SSE not supported; use POST /mcp.\n".utf8),
                    contentType: "text/plain; charset=utf-8"
                )
            default:
                return httpResponse(status: 404, body: Data("Route not found.\n".utf8), contentType: "text/plain; charset=utf-8")
            }
        case "POST":
            guard request.path == "/mcp" else {
                return httpResponse(status: 404, body: Data("Route not found.\n".utf8), contentType: "text/plain; charset=utf-8")
            }
        default:
            return httpResponse(status: 405, body: Data("Use POST /mcp for JSON-RPC requests.\n".utf8), contentType: "text/plain; charset=utf-8")
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
            throw MCPServerError.invalidRequest
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
        let parsedHeaders = parseHeaders(headerLines.dropFirst())
        return IncomingHTTPRequest(method: method, path: path, headers: parsedHeaders, body: body)
    }

    private func parseHeaders(_ lines: ArraySlice<String>) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let name = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            headers[name] = value
        }
        return headers
    }

    private func isAllowedOrigin(_ origin: String) -> Bool {
        if origin == "null" { return true }
        guard let url = URL(string: origin), let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }

        // Allow native-app origins (Electron/WebViews) while still blocking DNS rebinding.
        // These origins typically do not include a meaningful host.
        if let scheme = url.scheme?.lowercased() {
            if scheme == "codex" || scheme.hasPrefix("vscode") {
                return true
            }
        }

        return false
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

    private func httpResponse(status: Int, body: Data, contentType: String = "application/json") -> Data {
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
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n\r\n"

        return Data(response.utf8) + body
    }
}
