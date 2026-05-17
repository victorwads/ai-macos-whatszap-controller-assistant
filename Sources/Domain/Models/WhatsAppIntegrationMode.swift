import Foundation

enum WhatsAppIntegrationMode: String, Codable, CaseIterable, Identifiable {
    case web
    case desktopAX

    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: "WhatsApp Web (Embedded)"
        case .desktopAX: "WhatsApp Desktop (Accessibility)"
        }
    }
}

