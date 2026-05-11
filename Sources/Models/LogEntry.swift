import Foundation
import SwiftUI

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let level: LogLevel
    let message: String
}

enum LogLevel: String {
    case info
    case warning
    case error

    var color: Color {
        switch self {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}
