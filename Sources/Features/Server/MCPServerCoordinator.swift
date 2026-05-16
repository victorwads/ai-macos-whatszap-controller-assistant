import Foundation
import MCP

@MainActor
final class MCPServerCoordinator {
    private let dependencies: MCPServerContext
    private let connector = MCPHTTPServer()
    private var server: Server?
    private var sdkTransport: StatelessHTTPServerTransport?
    private var restartTask: Task<Void, Never>?
    private var stateHandler: (@MainActor (MCPServerState) -> Void)?
    private var callHandler: (@MainActor (MCPServerCallEntry) -> Void)?
    private var host = "localhost"
    private var port = 8080

    init(dependencies: MCPServerContext) {
        self.dependencies = dependencies
    }

    func setStateHandler(_ handler: @escaping @MainActor (MCPServerState) -> Void) {
        stateHandler = handler
    }

    func setCallHandler(_ handler: @escaping @MainActor (MCPServerCallEntry) -> Void) {
        callHandler = handler
    }

    var isRunning: Bool {
        connector.isRunning
    }

    func configure(host: String, port: Int) {
        self.host = host
        self.port = port
        connector.configure(host: host, port: port)
    }

    func start() async {
        connector.setStateHandler { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleStateChange(state)
            }
        }

        connector.setCallHandler { [weak self] entry in
            Task { @MainActor [weak self] in
                self?.callHandler?(entry)
            }
        }

        let sdkTransport = StatelessHTTPServerTransport()
        let server = Server(
            name: "assistant-whatsapp",
            version: "0.1.0",
            capabilities: .init(
                tools: .init(listChanged: true)
            )
        )
        let toolsSnapshot = MCPServerToolRegistry.toolDefinitions.map(makeMCPTool)

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: toolsSnapshot)
        }

        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else { return .init(content: [.text("Server unavailable")], isError: true) }

            let arguments = Self.jsonArguments(from: params.arguments)
            let result = await self.callTool(MCPToolCall(name: params.name, arguments: arguments))
            switch result {
            case .success(let value):
                return .init(content: [.text(Self.jsonText(from: value))], structuredContent: nil, isError: false)
            case .failure(let error):
                return .init(content: [.text(error.localizedDescription)], structuredContent: nil, isError: true)
            }
        }

        do {
            try await server.start(transport: sdkTransport)
            self.server = server
            self.sdkTransport = sdkTransport
            connector.setTransport(sdkTransport)
            try await connector.start()
        } catch {
            self.sdkTransport = nil
            await server.stop()
            await connector.stop()
            handleStateChange(.failed(message: error.localizedDescription))
            scheduleRestart()
        }
    }

    func stop() async {
        restartTask?.cancel()
        restartTask = nil
        await connector.stop()
        if let server {
            await server.stop()
        }
        self.server = nil
        self.sdkTransport = nil
    }

    func restart() async {
        await stop()
        await start()
    }

    private func scheduleRestart() {
        guard restartTask == nil else { return }
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.stateHandler?(.starting(port: self?.port ?? 8080))
            }
            await self?.start()
            await MainActor.run {
                self?.restartTask = nil
            }
        }
    }

    private func handleStateChange(_ state: MCPServerState) {
        stateHandler?(state)

        switch state {
        case .failed:
            scheduleRestart()
        case .ready, .stopped, .starting:
            break
        }
    }

    private func callTool(_ call: MCPToolCall) async -> Result<JSONValue, Error> {
        guard let tool = MCPServerToolRegistry.toolsByName[call.name] else {
            return .failure(MCPServerError.invalidParameter("name"))
        }
        return await tool.handle(call, context: dependencies)
    }

    private func makeMCPTool(_ definition: MCPToolDefinition) -> Tool {
        let schema = JSONValue.object(definition.inputSchema)
        return Tool(
            name: definition.name,
            title: nil,
            description: definition.description,
            inputSchema: Self.mcpValue(from: schema),
            annotations: nil,
            outputSchema: nil,
            icons: nil,
            _meta: nil
        )
    }

    nonisolated private static func jsonArguments(from value: [String: Value]?) -> [String: JSONValue] {
        guard let value else { return [:] }
        guard
            let data = try? JSONEncoder().encode(value),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object.compactMapValues { JSONValue.from(any: $0) }
    }

    nonisolated private static func mcpValue(from value: JSONValue) -> Value {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        if
            let data = try? encoder.encode(value),
            let decoded = try? decoder.decode(Value.self, from: data)
        {
            return decoded
        }
        return .null
    }

    nonisolated private static func jsonText(from value: JSONValue) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
