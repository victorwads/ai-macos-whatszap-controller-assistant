import Foundation
import MCP
import Network

final class MCPHTTPServer: MCPHTTPServerHosting, @unchecked Sendable {
    private final class StartResolution: @unchecked Sendable {
        var hasResolved = false
    }

    private let queue = DispatchQueue(label: "dev.wads.AssistantMCPServer.mcp", qos: .userInitiated)

    private var listener: NWListener?
    private var stateHandler: (@Sendable (MCPServerState) -> Void)?
    private(set) var isRunning = false
    private(set) var boundPort: Int = 8080
    private var host = "localhost"
    private var transport: StatelessHTTPServerTransport?

    func configure(host: String, port: Int) {
        self.host = host
        self.boundPort = port
    }

    func setStateHandler(_ handler: @escaping @Sendable (MCPServerState) -> Void) {
        self.stateHandler = handler
    }

    func setTransport(_ transport: StatelessHTTPServerTransport) {
        self.transport = transport
    }

    func start() async throws {
        guard listener == nil else {
            return
        }

        guard transport != nil else {
            throw MCPServerError.invalidParameter("transport")
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
                let payload = self.httpResponse(
                    status: 500,
                    body: Data("Internal Server Error.\n".utf8),
                    contentType: "text/plain; charset=utf-8"
                )
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
                let payload = self.httpResponse(
                    status: 400,
                    body: Data("Bad Request.\n".utf8),
                    contentType: "text/plain; charset=utf-8"
                )
                self.respond(on: connection, payload: payload)
                return
            }

            self.receiveRequest(on: connection, buffer: nextBuffer)
        }
    }

    private func process(request: IncomingHTTPRequest) async -> Data {
        guard let transport else {
            return httpResponse(status: 503, body: Data("MCP transport not configured.\n".utf8), contentType: "text/plain; charset=utf-8")
        }

        if request.method == "GET", request.path == "/health" {
            let payload = [
                "ok": true,
                "service": "AssistantMCPServer MCP bridge",
                "transport": "MCP Swift SDK (Stateless HTTP)",
                "endpoint": "http://\(host):\(boundPort)/mcp"
            ] as [String: Any]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            return httpResponse(status: 200, body: data)
        }

        if request.method == "GET", request.path == "/mcp" {
            let acceptHeader = request.headers["accept"]?.lowercased() ?? ""
            if !acceptHeader.contains("text/event-stream") {
                return httpResponse(
                    status: 405,
                    headers: ["allow": "POST"],
                    body: Data("Method Not Allowed.\n".utf8),
                    contentType: "text/plain; charset=utf-8"
                )
            }
        }

        var forwardedHeaders = request.headers
        if request.path == "/mcp" {
            let acceptHeader = forwardedHeaders["accept"]?.lowercased()
            let wantsJSON = acceptHeader?.contains("application/json") ?? false
            let wantsSSE = acceptHeader?.contains("text/event-stream") ?? false
            if acceptHeader == nil || acceptHeader == "*/*" || (!wantsJSON && !wantsSSE) {
                forwardedHeaders["accept"] = "application/json"
            }
        }

        let httpRequest = HTTPRequest(
            method: request.method,
            headers: forwardedHeaders,
            body: request.body,
            path: request.path
        )

        let response = await transport.handleRequest(httpRequest)
        return httpResponse(status: response.statusCode, headers: response.headers, body: response.bodyData ?? Data())
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

    private func respond(on connection: NWConnection, payload: Data) {
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func httpResponse(status: Int, headers: [String: String] = [:], body: Data, contentType: String? = nil) -> Data {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 403: statusText = "Forbidden"
        case 503: statusText = "Service Unavailable"
        default: statusText = "Internal Server Error"
        }

        var response = "HTTP/1.1 \(status) \(statusText)\r\n"
        response += "Host: \(host)\r\n"
        let resolvedContentType = contentType ?? headers["Content-Type"] ?? headers["content-type"] ?? "application/json"
        response += "Content-Type: \(resolvedContentType)\r\n"
        for (name, value) in headers where name.lowercased() != "content-type" && name.lowercased() != "content-length" && name.lowercased() != "connection" && name.lowercased() != "host" {
            response += "\(name): \(value)\r\n"
        }
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n\r\n"

        return Data(response.utf8) + body
    }
}
