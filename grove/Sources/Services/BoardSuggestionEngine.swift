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
    private static let suggestedBoard = "suggestedBoard"
    private static let pendingBoardSuggestion = "pendingBoardSuggestion"
    private static let mode = "suggestedBoardMode"
    private static let boardID = "suggestedBoardID"
    private static let confidence = "suggestedBoardConfidence"
    private static let reason = "suggestedBoardReason"
    private static let alternatives = "suggestedBoardAlternatives"

    static func apply(_ decision: BoardSuggestionDecision, to item: Item) {
        item.metadata[suggestedBoard] = decision.suggestedName
        item.metadata[pendingBoardSuggestion] = decision.suggestedName
        item.metadata[mode] = decision.mode.rawValue
        item.metadata[confidence] = decision.confidence.formatted(.number.precision(.fractionLength(2)))

        if let recommendedBoardID = decision.recommendedBoardID {
            item.metadata[boardID] = recommendedBoardID.uuidString
        } else {
            item.metadata[boardID] = nil
        }

        if decision.reason.isEmpty {
            item.metadata[reason] = nil
        } else {
            item.metadata[reason] = decision.reason
        }

        if decision.alternativeBoardIDs.isEmpty {
            item.metadata[alternatives] = nil
        } else {
            item.metadata[alternatives] = decision.alternativeBoardIDs.map(\.uuidString).joined(separator: ",")
        }
    }

    static func clearPendingSuggestion(on item: Item) {
        item.metadata[pendingBoardSuggestion] = nil
    }

    /// Preserve a local, privacy-safe correction signal before resolving the
    /// pending suggestion. These fields can seed OS 27 evaluation datasets
    /// without storing prompt text or sending analytics off-device.
    static func recordSelection(_ board: Board, on item: Item) {
        let decision = decision(from: item)
        item.metadata["boardSuggestionOutcome"] = "selected"
        item.metadata["boardSuggestionSelectedBoardID"] = board.id.uuidString
        item.metadata["boardSuggestionMatchedRecommendation"] =
            decision?.recommendedBoardID == board.id ? "true" : "false"
        item.metadata["boardSuggestionResolvedAt"] = Date.now.ISO8601Format()
        clearPendingSuggestion(on: item)
    }

    static func decision(from item: Item) -> BoardSuggestionDecision? {
        let suggestedName = cleanedSuggestionName(from: item)
        guard !suggestedName.isEmpty else { return nil }

        let suggestionMode = BoardSuggestionMode(rawValue: item.metadata[mode] ?? "") ?? .create
        let recommendedBoardID = item.metadata[boardID].flatMap(UUID.init(uuidString:))
        let confidenceValue = item.metadata[confidence].flatMap(Double.init) ?? 0
        let reasonText = item.metadata[reason] ?? ""
        let alternativeIDs = parseAlternativeIDs(item.metadata[alternatives])

        return BoardSuggestionDecision(
            suggestedName: suggestedName,
            mode: suggestionMode,
            recommendedBoardID: recommendedBoardID,
            confidence: confidenceValue,
            reason: reasonText,
            alternativeBoardIDs: alternativeIDs
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
        let raw = item.metadata[pendingBoardSuggestion] ?? item.metadata[suggestedBoard] ?? ""
        return BoardSuggestionEngine.cleanedBoardName(raw)
    }

    private static func parseAlternativeIDs(_ rawValue: String?) -> [UUID] {
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
        let titleSimilarity = TagService.nameSimilarity(suggestedName, board.title)
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
}
