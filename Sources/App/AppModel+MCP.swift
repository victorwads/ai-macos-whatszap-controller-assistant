import Foundation

extension AppModel {
    var mcpServerAddress: String {
        "\(mcpServerHost):\(mcpServerPort)"
    }

    var mcpConfigurationSnippet: String {
        """
        [mcp_servers.assistant_whatsapp]
        enabled = true
        url = "http://localhost:\(mcpServerPort)/mcp"
        """
    }

    func updateMCPServerPortText(_ value: String) {
        let digitsOnly = String(value.filter(\.isNumber))
        let trimmedDigits = String(digitsOnly.prefix(5))
        mcpServerPortText = trimmedDigits

        guard let port = Int(trimmedDigits), (1024...65535).contains(port) else {
            return
        }

        mcpServerPort = port
    }

    func startMCPServer() async {
        mcpServerCoordinator.configure(host: mcpServerHost, port: mcpServerPort)
        await mcpServerCoordinator.start()
    }

    func stopMCPServer() async {
        await mcpServerCoordinator.stop()
        mcpServerRunning = false
        mcpServerStatusDescription = "Stopped"
    }

    func restartMCPServer() async {
        await stopMCPServer()
        await startMCPServer()
    }

    func handleMCPStateChange(_ state: MCPServerState) {
        switch state {
        case .starting(let port):
            mcpServerRunning = false
            mcpServerStatusDescription = "Starting on localhost:\(port)"
            appendLog("Starting MCP HTTP server on localhost:\(port).")
        case .ready(let port):
            mcpServerRunning = true
            mcpServerStatusDescription = "Listening on localhost:\(port)"
            appendLog("MCP HTTP server listening on localhost:\(port).")
        case .failed(let message):
            mcpServerRunning = false
            mcpServerStatusDescription = "Failed: \(message)"
            appendLog("MCP HTTP server failed: \(message)", level: .error)
        case .stopped:
            mcpServerRunning = false
            mcpServerStatusDescription = "Stopped"
            appendLog("MCP HTTP server stopped.", level: .warning)
        }
    }
}
