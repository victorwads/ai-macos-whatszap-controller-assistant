import Foundation

enum TextSimilarity {
    static func score(query: String, candidate: String) -> Double {
        let normalizedQuery = normalize(query)
        let normalizedCandidate = normalize(candidate)

        guard !normalizedQuery.isEmpty, !normalizedCandidate.isEmpty else {
            return 0
        }

        if normalizedQuery == normalizedCandidate {
            return 1
        }

        var score = 0.0

        if normalizedCandidate.contains(normalizedQuery) {
            score += 0.35
        }

        if normalizedQuery.contains(normalizedCandidate) {
            score += 0.12
        }

        score += tokenDiceCoefficient(normalizedQuery, normalizedCandidate) * 0.35
        score += trigramJaccard(normalizedQuery, normalizedCandidate) * 0.30

        return min(score, 1)
    }

    static func bestScore(query: String, candidates: [String]) -> Double {
        candidates.map { score(query: query, candidate: $0) }.max() ?? 0
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let lowered = folded.lowercased()
        let separators = lowered.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return " "
        }

        return String(separators)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenDiceCoefficient(_ left: String, _ right: String) -> Double {
        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))

        guard !leftTokens.isEmpty, !rightTokens.isEmpty else {
            return 0
        }

        let intersection = Double(leftTokens.intersection(rightTokens).count)
        return (2.0 * intersection) / Double(leftTokens.count + rightTokens.count)
    }

    private static func trigramJaccard(_ left: String, _ right: String) -> Double {
        let leftTrigrams = trigrams(for: left)
        let rightTrigrams = trigrams(for: right)

        guard !leftTrigrams.isEmpty, !rightTrigrams.isEmpty else {
            return 0
        }

        let intersection = Double(leftTrigrams.intersection(rightTrigrams).count)
        let union = Double(leftTrigrams.union(rightTrigrams).count)

        guard union > 0 else { return 0 }
        return intersection / union
    }

    private static func trigrams(for value: String) -> Set<String> {
        let characters = Array(value)
        guard !characters.isEmpty else { return [] }
        guard characters.count >= 3 else { return [value] }

        var result: Set<String> = []
        for index in 0..<(characters.count - 2) {
            let slice = characters[index..<(index + 3)]
            result.insert(String(slice))
        }
        return result
    }
}
