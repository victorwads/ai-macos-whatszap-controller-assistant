import Foundation

struct MemorySearchResult: Codable, Equatable {
    let entry: MemoryEntry
    let score: Double
}
