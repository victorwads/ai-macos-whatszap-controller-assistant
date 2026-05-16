import Foundation

struct SearchContactChatsTool: MCPToolHandler {
    static let definition = MCPToolDefinition(
        name: "search_contact_chats",
        description: "Searches mapped WhatsApp chats by contact name and returns the best matches.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")])
            ]),
            "required": .array([.string("query")])
        ],
        exampleParameters: [
            .init(name: "query", value: .string("Leonardo")),
            .init(name: "limit", value: .number(3))
        ],
        traits: [.readOnly]
    )

    static func handle(_ call: MCPToolCall, context: MCPServerContext) async -> Result<JSONValue, Error> {
        let arguments = MCPToolArguments(values: call.arguments)
        guard let rawQuery = arguments.string(for: "query", "term", "search")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawQuery.isEmpty else {
            return .failure(MCPServerError.missingParameter("query"))
        }

        let limit = max(1, arguments.int(for: "limit") ?? 3)
        let chats = await MainActor.run {
            context.memoryStore.conversations
                .filter { !context.isBlocked($0.name) }
                .compactMap { conversation -> (ConversationSummary, Double)? in
                    let score = searchScore(query: rawQuery, candidate: conversation.name)
                    guard score > 0 else { return nil }
                    return (conversation, score)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
                }
                .prefix(limit)
                .map { conversation, _ in context.conversationJSONValue(conversation) }
        }

        return .success(.object(["chats": .array(chats)]))
    }

    private static func searchScore(query: String, candidate: String) -> Double {
        let normalizedQuery = normalize(query)
        let normalizedCandidate = normalize(candidate)

        guard !normalizedQuery.isEmpty, !normalizedCandidate.isEmpty else {
            return 0
        }

        if normalizedQuery == normalizedCandidate {
            return 1
        }

        let queryCompact = normalizedQuery.replacingOccurrences(of: " ", with: "")
        let candidateCompact = normalizedCandidate.replacingOccurrences(of: " ", with: "")

        if candidateCompact.hasPrefix(queryCompact) {
            return 0.98
        }

        if candidateCompact.contains(queryCompact) {
            return 0.94
        }

        let queryTokens = tokenize(normalizedQuery)
        let candidateTokens = tokenize(normalizedCandidate)

        if queryTokens.isEmpty || candidateTokens.isEmpty {
            return diceCoefficient(queryCompact, candidateCompact) * 0.65
        }

        let tokenSetScore = jaccard(queryTokens, candidateTokens)
        let tokenPrefixScore = tokenPrefixMatch(queryTokens: queryTokens, candidateTokens: candidateTokens)
        let diceScore = diceCoefficient(queryCompact, candidateCompact)

        return max(tokenPrefixScore, max(tokenSetScore * 0.9, diceScore * 0.75))
    }

    private static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        let lowercased = folded.lowercased()
        let allowed = lowercased.map { character -> Character in
            if character.isLetter || character.isNumber || character.isWhitespace {
                return character
            }
            return " "
        }
        return String(allowed)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func jaccard(_ lhs: [String], _ rhs: [String]) -> Double {
        let left = Set(lhs)
        let right = Set(rhs)
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private static func tokenPrefixMatch(queryTokens: [String], candidateTokens: [String]) -> Double {
        var best: Double = 0
        for queryToken in queryTokens {
            for candidateToken in candidateTokens {
                if candidateToken == queryToken {
                    best = max(best, 1)
                } else if candidateToken.hasPrefix(queryToken) || queryToken.hasPrefix(candidateToken) {
                    let shorter = Double(min(queryToken.count, candidateToken.count))
                    let longer = Double(max(queryToken.count, candidateToken.count))
                    let ratio = longer > 0 ? shorter / longer : 0
                    best = max(best, 0.9 + (ratio * 0.05))
                }
            }
        }
        return best
    }

    private static func diceCoefficient(_ lhs: String, _ rhs: String) -> Double {
        let leftBigrams = bigrams(for: lhs)
        let rightBigrams = bigrams(for: rhs)
        guard !leftBigrams.isEmpty || !rightBigrams.isEmpty else { return 0 }
        let intersection = leftBigrams.intersection(rightBigrams).count
        return Double(2 * intersection) / Double(leftBigrams.count + rightBigrams.count)
    }

    private static func bigrams(for text: String) -> Set<String> {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 2 else {
            return compact.isEmpty ? [] : Set([compact])
        }

        let characters = Array(compact)
        var result: Set<String> = []
        for index in 0..<(characters.count - 1) {
            result.insert(String(characters[index...(index + 1)]))
        }
        return result
    }
}
