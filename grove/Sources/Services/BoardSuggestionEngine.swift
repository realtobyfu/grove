import Foundation
import SwiftData

enum BoardSuggestionMode: String {
    case existing
    case create
}

struct BoardSuggestionDecision: Equatable {
    let suggestedName: String
    let mode: BoardSuggestionMode
    let recommendedBoardID: UUID?
    let confidence: Double
    let reason: String
    let alternativeBoardIDs: [UUID]
}

enum BoardSuggestionMetadata {
    static func apply(_ decision: BoardSuggestionDecision, to item: Item) {
        item.suggestedBoard = decision.suggestedName
        item.pendingBoardSuggestion = decision.suggestedName
        item.suggestedBoardMode = decision.mode
        item.suggestedBoardConfidence = decision.confidence
        item.suggestedBoardID = decision.recommendedBoardID
        item.suggestedBoardReason = decision.reason.isEmpty ? nil : decision.reason
        item.suggestedBoardAlternativeIDs = decision.alternativeBoardIDs
    }

    static func clearPendingSuggestion(on item: Item) {
        item.pendingBoardSuggestion = nil
    }

    static func decision(from item: Item) -> BoardSuggestionDecision? {
        let suggestedName = cleanedSuggestionName(from: item)
        guard !suggestedName.isEmpty else { return nil }

        return BoardSuggestionDecision(
            suggestedName: suggestedName,
            mode: item.suggestedBoardMode ?? .create,
            recommendedBoardID: item.suggestedBoardID,
            confidence: item.suggestedBoardConfidence ?? 0,
            reason: item.suggestedBoardReason ?? "",
            alternativeBoardIDs: item.suggestedBoardAlternativeIDs
        )
    }

    static func decision(from notification: Notification) -> (itemID: UUID, decision: BoardSuggestionDecision)? {
        guard let userInfo = notification.userInfo,
              let itemID = userInfo["itemID"] as? UUID,
              let rawBoardName = userInfo["boardName"] as? String else {
            return nil
        }

        let suggestedName = BoardSuggestionEngine.cleanedBoardName(rawBoardName)
        guard !suggestedName.isEmpty else { return nil }

        let suggestionMode = (userInfo["mode"] as? String).flatMap(BoardSuggestionMode.init(rawValue:)) ?? .create

        let recommendedBoardID: UUID?
        if let idString = userInfo["boardID"] as? String {
            recommendedBoardID = UUID(uuidString: idString)
        } else {
            recommendedBoardID = nil
        }

        let confidenceValue: Double
        if let confidence = userInfo["confidence"] as? Double {
            confidenceValue = confidence
        } else if let confidenceString = userInfo["confidence"] as? String,
                  let confidence = Double(confidenceString) {
            confidenceValue = confidence
        } else {
            confidenceValue = 0
        }

        let reasonText = userInfo["reason"] as? String ?? ""
        let alternativesString = userInfo["alternatives"] as? String
        let alternativeIDs = parseAlternativeIDs(alternativesString)

        let decision = BoardSuggestionDecision(
            suggestedName: suggestedName,
            mode: suggestionMode,
            recommendedBoardID: recommendedBoardID,
            confidence: confidenceValue,
            reason: reasonText,
            alternativeBoardIDs: alternativeIDs
        )

        return (itemID: itemID, decision: decision)
    }

    static func notificationUserInfo(itemID: UUID, decision: BoardSuggestionDecision, isColdStart: Bool) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [
            "itemID": itemID,
            "boardName": decision.suggestedName,
            "isColdStart": isColdStart,
            "mode": decision.mode.rawValue,
            "confidence": decision.confidence
        ]

        if let recommendedBoardID = decision.recommendedBoardID {
            userInfo["boardID"] = recommendedBoardID.uuidString
        }

        if !decision.reason.isEmpty {
            userInfo["reason"] = decision.reason
        }

        if !decision.alternativeBoardIDs.isEmpty {
            userInfo["alternatives"] = decision.alternativeBoardIDs.map(\.uuidString).joined(separator: ",")
        }

        return userInfo
    }

    private static func cleanedSuggestionName(from item: Item) -> String {
        let raw = item.pendingBoardSuggestion ?? item.suggestedBoard ?? ""
        return BoardSuggestionEngine.cleanedBoardName(raw)
    }

    static func parseAlternativeIDs(_ rawValue: String?) -> [UUID] {
        guard let rawValue, !rawValue.isEmpty else { return [] }
        return rawValue
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }
}

/// Protocol for board suggestion engine.
@MainActor
protocol BoardSuggestionEngineProtocol {
    func resolveSuggestion(for item: Item, suggestedName: String, boards: [Board]) -> BoardSuggestionDecision
}

@MainActor
struct BoardSuggestionEngine: BoardSuggestionEngineProtocol {
    private struct Candidate {
        let board: Board
        let score: Double
        let titleSimilarity: Double
        let tokenOverlap: Double
        let tagOverlap: Double
        let exactNameMatch: Bool
    }

    func resolveSuggestion(for item: Item, suggestedName rawSuggestedName: String, boards: [Board]) -> BoardSuggestionDecision {
        let suggestedName = Self.cleanedBoardName(rawSuggestedName)
        guard !suggestedName.isEmpty else {
            return BoardSuggestionDecision(
                suggestedName: "General",
                mode: .create,
                recommendedBoardID: nil,
                confidence: 0.6,
                reason: "Suggestion was too vague for existing board matching.",
                alternativeBoardIDs: []
            )
        }

        guard !boards.isEmpty else {
            return BoardSuggestionDecision(
                suggestedName: suggestedName,
                mode: .create,
                recommendedBoardID: nil,
                confidence: 1,
                reason: "No boards exist yet.",
                alternativeBoardIDs: []
            )
        }

        let itemTagNames = Set(item.tags.map { Self.normalizeToken($0.name) })

        let candidates = boards
            .map { scoreCandidate($0, suggestedName: suggestedName, itemTagNames: itemTagNames) }
            .sorted { $0.score > $1.score }

        guard let best = candidates.first else {
            return BoardSuggestionDecision(
                suggestedName: suggestedName,
                mode: .create,
                recommendedBoardID: nil,
                confidence: 0.8,
                reason: "No boards were available for comparison.",
                alternativeBoardIDs: []
            )
        }

        let threshold = 0.72
        let shouldUseExisting = best.exactNameMatch || best.score >= threshold

        if shouldUseExisting {
            let alternatives = candidates
                .dropFirst()
                .filter { $0.score >= 0.42 }
                .prefix(3)
                .map(\.board.id)

            return BoardSuggestionDecision(
                suggestedName: best.board.title,
                mode: .existing,
                recommendedBoardID: best.board.id,
                confidence: best.score,
                reason: reasonForExistingMatch(best),
                alternativeBoardIDs: alternatives
            )
        }

        let alternatives = candidates
            .filter { $0.score >= 0.35 }
            .prefix(3)
            .map(\.board.id)

        let creationConfidence = max(0.55, 1 - (best.score * 0.8))
        let reason = reasonForNewBoard(best)

        return BoardSuggestionDecision(
            suggestedName: suggestedName,
            mode: .create,
            recommendedBoardID: nil,
            confidence: creationConfidence,
            reason: reason,
            alternativeBoardIDs: alternatives
        )
    }

    nonisolated static func cleanedBoardName(_ raw: String) -> String {
        let collapsedWhitespace = raw
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
        return collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func confidenceLabel(for confidence: Double) -> String {
        switch confidence {
        case 0.85...:
            return "High confidence"
        case 0.65..<0.85:
            return "Medium confidence"
        default:
            return "Low confidence"
        }
    }

    private func scoreCandidate(
        _ board: Board,
        suggestedName: String,
        itemTagNames: Set<String>
    ) -> Candidate {
        let titleSimilarity = Self.nameSimilarity(suggestedName, board.title)
        let tokenOverlap = jaccard(tokens(from: suggestedName), tokens(from: board.title))

        let boardTagNames = Set(
            board.items
                .flatMap { $0.tags.map { Self.normalizeToken($0.name) } }
        )

        let tagOverlap: Double
        if itemTagNames.isEmpty || boardTagNames.isEmpty {
            tagOverlap = 0
        } else {
            let intersection = itemTagNames.intersection(boardTagNames).count
            tagOverlap = Double(intersection) / Double(itemTagNames.count)
        }

        let activityScore = recentActivityScore(for: board)

        var total = (titleSimilarity * 0.58)
            + (tokenOverlap * 0.17)
            + (tagOverlap * 0.20)
            + (activityScore * 0.05)

        let exactNameMatch = board.title.localizedCaseInsensitiveCompare(suggestedName) == .orderedSame
        if exactNameMatch {
            total = max(total, 0.98)
        }

        total = max(0, min(total, 1))

        return Candidate(
            board: board,
            score: total,
            titleSimilarity: titleSimilarity,
            tokenOverlap: tokenOverlap,
            tagOverlap: tagOverlap,
            exactNameMatch: exactNameMatch
        )
    }

    private func reasonForExistingMatch(_ candidate: Candidate) -> String {
        var parts: [String] = []

        if candidate.exactNameMatch {
            parts.append("exact board name match")
        } else if candidate.titleSimilarity >= 0.78 {
            parts.append("strong name similarity")
        } else if candidate.tokenOverlap >= 0.4 {
            parts.append("shared title keywords")
        }

        if candidate.tagOverlap >= 0.3 {
            parts.append("tag overlap")
        }

        if parts.isEmpty {
            return "closest existing board by content and naming"
        }

        return parts.prefix(2).joined(separator: " + ")
    }

    private func reasonForNewBoard(_ bestCandidate: Candidate) -> String {
        if bestCandidate.score >= 0.5 {
            return "No strong match. Closest board was \"\(bestCandidate.board.title)\"."
        }
        return "No close existing board match."
    }

    private func recentActivityScore(for board: Board) -> Double {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -45, to: .now) else { return 0 }

        let recentCount = board.items.reduce(into: 0) { partialResult, item in
            if item.updatedAt >= cutoff {
                partialResult += 1
            }
        }

        return min(Double(recentCount) / 8.0, 1)
    }

    private func tokens(from text: String) -> Set<String> {
        TextTokenizer.tokenize(text, minLength: 2)
    }

    private static func normalizeToken(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "")
    }

    private func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        TextTokenizer.jaccardSimilarity(a, b)
    }

    /// String similarity between two names using normalized edit distance
    /// (1.0 = identical once case and separators are ignored).
    nonisolated static func nameSimilarity(_ a: String, _ b: String) -> Double {
        let s1 = normalizeName(a)
        let s2 = normalizeName(b)

        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }

        let distance = levenshteinDistance(s1, s2)
        let maxLen = max(s1.count, s2.count)
        return 1.0 - Double(distance) / Double(maxLen)
    }

    /// Lowercase and strip separators so "machine-learning" matches "Machine Learning".
    private nonisolated static func normalizeName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private nonisolated static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,       // deletion
                    curr[j - 1] + 1,   // insertion
                    prev[j - 1] + cost // substitution
                )
            }
            prev = curr
        }

        return prev[n]
    }
}
