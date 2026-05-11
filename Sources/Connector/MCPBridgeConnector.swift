import Foundation

protocol MCPBridgeConnecting {
    func start() async throws
    func stop() async
}

final class MCPBridgeConnector: MCPBridgeConnecting {
    func start() async throws {}

    func stop() async {}
}
