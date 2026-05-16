import Foundation

enum MCPServerState: Equatable {
    case starting(port: Int)
    case ready(port: Int)
    case failed(message: String)
    case stopped
}
