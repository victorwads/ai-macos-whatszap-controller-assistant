import Foundation
import MCP

protocol MCPHTTPServerHosting: AnyObject {
    var isRunning: Bool { get }
    var boundPort: Int { get }

    func configure(host: String, port: Int)
    func setStateHandler(_ handler: @escaping @Sendable (MCPServerState) -> Void)
    func setTransport(_ transport: StatelessHTTPServerTransport)

    func start() async throws
    func stop() async
}

