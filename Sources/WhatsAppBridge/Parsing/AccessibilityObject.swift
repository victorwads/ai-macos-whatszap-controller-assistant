import Foundation

struct AccessibilityObject {
    let root: RawAXNode

    func node(at dotPath: String) -> RawAXNode? {
        root.node(at: dotPath)
    }

    func node(at path: [Int]) -> RawAXNode? {
        root.node(at: path)
    }

    func firstDescendant(where predicate: (RawAXNode) -> Bool) -> RawAXNode? {
        root.firstDescendant(where: predicate)
    }

    func containsText(matching needles: [String]) -> Bool {
        let haystack = root.textFragments.joined(separator: " ").lowercased()
        return needles.contains { haystack.contains($0) }
    }
}
