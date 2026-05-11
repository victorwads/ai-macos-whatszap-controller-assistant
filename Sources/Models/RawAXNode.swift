import CoreGraphics
import Foundation

struct RawAXNode: Identifiable, Equatable {
    let id = UUID()
    let accessibilityPath: [Int]
    let role: String?
    let subrole: String?
    let title: String?
    let nodeDescription: String?
    let help: String?
    let stringValue: String?
    let frame: CGRect?
    let children: [RawAXNode]

    var ownTextFragments: [String] {
        [title, nodeDescription, help, stringValue].compactMap { value in
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            return text
        }
    }

    var textFragments: [String] {
        ownTextFragments + children.flatMap(\.textFragments)
    }

    var flattened: [RawAXNode] {
        [self] + children.flatMap(\.flattened)
    }

    func prettyDescription(depth: Int = 0) -> String {
        let indent = String(repeating: "  ", count: depth)
        var parts: [String] = []

        if !accessibilityPath.isEmpty {
            parts.append("path=\(accessibilityPath.map(String.init).joined(separator: "."))")
        }
        if let role, !role.isEmpty {
            parts.append("role=\(role)")
        }
        if let subrole, !subrole.isEmpty {
            parts.append("subrole=\(subrole)")
        }
        if let title, !title.isEmpty {
            parts.append("title=\(title)")
        }
        if let nodeDescription, !nodeDescription.isEmpty {
            parts.append("description=\(nodeDescription)")
        }
        if let help, !help.isEmpty {
            parts.append("help=\(help)")
        }
        if let stringValue, !stringValue.isEmpty {
            parts.append("value=\(stringValue)")
        }
        if let frame {
            parts.append("frame=(x:\(Int(frame.origin.x)), y:\(Int(frame.origin.y)), w:\(Int(frame.width)), h:\(Int(frame.height)))")
        }

        let line = parts.isEmpty ? "-" : "- \(parts.joined(separator: ", "))"
        let childLines = children.map { $0.prettyDescription(depth: depth + 1) }
        return ([indent + line] + childLines).joined(separator: "\n")
    }
}
