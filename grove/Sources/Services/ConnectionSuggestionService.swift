import Foundation
import SwiftData

/// A suggested connection between two items, with a recommended type and relevance score.
struct ConnectionSuggestion: Identifiable {
    let id = UUID()
    let targetItem: Item
    let suggestedType: ConnectionType
    let score: Double
    let reason: String
}

/// Protocol for connection suggestion services.
@MainActor
protocol ConnectionSuggestionServiceProtocol {
    func suggestConnections(for sourceItem: Item, maxResults: Int) -> [ConnectionSuggestion]
    func suggestConnectionsAsync(for sourceItem: Item, maxResults: Int) async -> [ConnectionSuggestion]
    func dismissSuggestion(sourceItemID: UUID, targetItemID: UUID)
    func recordAccepted(sourceItem: Item, targetItem: Item)
}

/// LLM response shape for connection suggestions.
private struct ConnectionSuggestionResponse: Decodable {
    struct Suggestion: Decodable {
        let target_title: String
        let connection_type: String
        let score: Double?     // 0.0–1.0 confidence; required for auto-connect, optional for UI suggestions
        let reason: String
    }
    let suggestions: [Suggestion]
}

/// Analyzes items to suggest connections using LLM intelligence with heuristic fallback.
/// Sends item context + candidate list to LLM for semantic analysis.
/// Falls back to keyword/tag overlap heuristics if LLM is unavailable.
/// Respects dismissed suggestions per item pair.
@MainActor
@Observable
final class ConnectionSuggestionService: ConnectionSuggestionServiceProtocol {
    private var modelContext: ModelContext
    private let provider: LLMProvider

    /// Key: "sourceID-targetID" (sorted), Value: Date dismissed
    /// Persisted in UserDefaults to survive across sessions.
    private static let dismissedKey = "grove.dismissedConnectionSuggestions"

    init(modelContext: ModelContext, provider: LLMProvider = LLMServiceConfig.makeProvider()) {
        self.modelContext = modelContext
        self.provider = provider
    }

    // MARK: - LLM-Backed Suggestions (Primary)

    /// Suggest connections using the LLM. Falls back to heuristic method if LLM fails.
    /// Call this from async contexts (Task blocks) for best results.
    func suggestConnectionsAsync(for sourceItem: Item, maxResults: Int = 3) async -> [ConnectionSuggestion] {
        guard EntitlementService.shared.canUse(.connectionSuggestions) else { return [] }
        // Try LLM first if configured
        if LLMServiceConfig.isConfigured,
           sourceItem.content != nil || !sourceItem.reflections.isEmpty {
            let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
            let candidates = filterCandidates(for: sourceItem, from: allItems)

            if !candidates.isEmpty {
                let llmSuggestions = await suggestWithLLM(
                    sourceItem: sourceItem,
                    candidates: candidates,
                    maxResults: maxResults
                )
                if !llmSuggestions.isEmpty {
                    EntitlementService.shared.recordUse(.connectionSuggestions)
                    return llmSuggestions
                }
            }
        }

        // Fallback to heuristic
        let heuristic = suggestConnections(for: sourceItem, maxResults: maxResults)
        if !heuristic.isEmpty {
            EntitlementService.shared.recordUse(.connectionSuggestions)
        }
        return heuristic
    }

    /// Query the LLM for semantic connection suggestions.
    private func suggestWithLLM(
        sourceItem: Item,
        candidates: [Item],
        maxResults: Int
    ) async -> [ConnectionSuggestion] {
        let systemPrompt = """
        You are a knowledge-management assistant. Given a source item and a list of candidate items, \
        identify which candidates are most meaningfully connected to the source.

        Return a JSON object with:
        - "suggestions": an array of objects, each with:
          - "target_title": the exact title of the candidate item
          - "connection_type": one of "related", "contradicts", "buildsOn", "inspiredBy", "sameTopic"
          - "reason": a brief explanation (1 sentence, max 80 characters) of why they are connected

        Rules:
        - Return 1-\(maxResults) suggestions, only for genuinely meaningful connections.
        - Prefer specific reasoning ("both discuss X") over generic ("similar topic").
        - "contradicts" means the items present opposing views on the same subject.
        - "buildsOn" means the target extends, deepens, or applies ideas from the source.
        - "inspiredBy" means the source clearly influenced or motivated the target.
        - "sameTopic" means they cover the same subject from different angles.
        - "related" is the default for general thematic overlap.
        - Only return valid JSON, no extra text.
        """

        let sourceDesc = LLMContextBuilder.itemDescription(sourceItem)
        let candidateList = LLMContextBuilder.itemList(Array(candidates.prefix(AppConstants.LLM.maxCandidateItems)))

        let userPrompt = """
        SOURCE ITEM:
        \(sourceDesc)

        CANDIDATE ITEMS:
        \(candidateList)
        """

        guard let result = await provider.complete(system: systemPrompt, user: userPrompt, service: "suggestions") else {
            return []
        }

        guard let parsed = LLMJSONParser.decode(ConnectionSuggestionResponse.self, from: result.content) else {
            return []
        }

        // Map LLM response back to actual Item objects by title
        let candidatesByTitle = Dictionary(
            candidates.map { ($0.title.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var suggestions: [ConnectionSuggestion] = []
        for entry in parsed.suggestions.prefix(maxResults) {
            let normalizedTitle = entry.target_title.lowercased()
            guard let targetItem = candidatesByTitle[normalizedTitle],
                  targetItem.id != sourceItem.id else { continue }

            let connectionType = ConnectionType(rawValue: entry.connection_type) ?? .related
            let reason = String(entry.reason.prefix(AppConstants.LLM.reasonMaxLength))

            suggestions.append(ConnectionSuggestion(
                targetItem: targetItem,
                suggestedType: connectionType,
                score: 1.0,
                reason: reason
            ))
        }

        return suggestions
    }

    /// Filter all items down to valid candidates (not self, not connected, not dismissed).
    private func filterCandidates(for sourceItem: Item, from allItems: [Item]) -> [Item] {
        let connectedIDs = Set(
            sourceItem.outgoingConnections.compactMap(\.targetItem?.id) +
            sourceItem.incomingConnections.compactMap(\.sourceItem?.id)
        )
        let dismissed = Self.loadDismissed()

        return allItems.filter { candidate in
            guard candidate.id != sourceItem.id else { return false }
            guard !connectedIDs.contains(candidate.id) else { return false }
            let pairKey = Self.pairKey(sourceItem.id, candidate.id)
            return dismissed[pairKey] == nil
        }
    }

    // MARK: - Heuristic Suggestions (Fallback)

    /// Analyze a source item against all other items and return top suggestions.
    /// Synchronous heuristic fallback — used when LLM is unavailable.
    func suggestConnections(for sourceItem: Item, maxResults: Int = 3) -> [ConnectionSuggestion] {
        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []

        // Existing connection target IDs (both directions)
        let connectedIDs = Set(
            sourceItem.outgoingConnections.compactMap(\.targetItem?.id) +
            sourceItem.incomingConnections.compactMap(\.sourceItem?.id)
        )

        let dismissed = Self.loadDismissed()
        let sourceWords = extractKeywords(from: sourceItem)
        let sourceTagIDs = Set(sourceItem.tags.map(\.id))

        var scored: [(Item, Double, ConnectionType, String)] = []

        for candidate in allItems {
            // Skip self, already connected, and dismissed pairs
            guard candidate.id != sourceItem.id else { continue }
            guard !connectedIDs.contains(candidate.id) else { continue }

            let pairKey = Self.pairKey(sourceItem.id, candidate.id)
            if dismissed[pairKey] != nil { continue }

            let candidateWords = extractKeywords(from: candidate)
            let candidateTagIDs = Set(candidate.tags.map(\.id))

            // Score components
            var totalScore: Double = 0
            var reasons: [String] = []

            // 1. Tag overlap (strongest signal)
            let sharedTagIDs = sourceTagIDs.intersection(candidateTagIDs)
            if !sharedTagIDs.isEmpty {
                let tagScore = Double(sharedTagIDs.count) * 0.3
                totalScore += min(tagScore, 0.9)
                let sharedTagNames = sourceItem.tags
                    .filter { sharedTagIDs.contains($0.id) }
                    .map(\.name)
                reasons.append("shared tags: \(sharedTagNames.joined(separator: ", "))")
            }

            // 2. Title similarity
            let titleSim = TextTokenizer.jaccardSimilarity(sourceWords.titleWords, candidateWords.titleWords)
            if titleSim > 0.1 {
                totalScore += titleSim * 0.4
                reasons.append("similar titles")
            }

            // 3. Content keyword overlap
            let contentSim = TextTokenizer.jaccardSimilarity(sourceWords.contentWords, candidateWords.contentWords)
            if contentSim > 0.05 {
                totalScore += contentSim * 0.3
                reasons.append("overlapping content")
            }

            // 4. Board overlap bonus
            let sourceBoardIDs = Set(sourceItem.boards.map(\.id))
            let candidateBoardIDs = Set(candidate.boards.map(\.id))
            if !sourceBoardIDs.intersection(candidateBoardIDs).isEmpty {
                totalScore += 0.1
            }

            // Minimum threshold
            guard totalScore >= AppConstants.Scoring.connectionSuggestionFloor else { continue }

            let suggestedType = inferConnectionType(
                sourceItem: sourceItem,
                candidate: candidate,
                sharedTagCount: sharedTagIDs.count
            )
            let reason = reasons.isEmpty ? "content similarity" : reasons.joined(separator: ", ")

            scored.append((candidate, totalScore, suggestedType, reason))
        }

        // Sort by score descending, take top N
        scored.sort { $0.1 > $1.1 }
        return scored.prefix(maxResults).map { item, score, type, reason in
            ConnectionSuggestion(
                targetItem: item,
                suggestedType: type,
                score: score,
                reason: reason
            )
        }
    }

    // MARK: - Auto-Connection (Persist High-Confidence Links)

    /// Automatically creates and persists high-confidence connections for the given item.
    /// Fires silently after item capture — degrades gracefully if LLM is unavailable.
    /// Caps at 2 auto-connections per item. Requires at least 5 other items for signal.
    func autoConnect(item: Item, in context: ModelContext) async {
        guard EntitlementService.shared.canUse(.connectionSuggestions) else { return }
        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []

        // Need at least 5 other items for meaningful signal
        let otherItems = allItems.filter { $0.id != item.id }
        guard otherItems.count >= AppConstants.Scoring.minItemsForAutoConnect else { return }

        // Skip items already connected in either direction
        let connectedIDs = Set(
            item.outgoingConnections.compactMap(\.targetItem?.id) +
            item.incomingConnections.compactMap(\.sourceItem?.id)
        )
        let candidates = otherItems.filter { !connectedIDs.contains($0.id) }
        guard !candidates.isEmpty else { return }

        var suggestions: [ConnectionSuggestion] = []

        // LLM path: stricter prompt requiring score ≥ 0.7
        if LLMServiceConfig.isConfigured {
            suggestions = await autoConnectWithLLM(item: item, candidates: candidates)
        }

        // Heuristic fallback: only very strong signals (≥ 0.5, well above the 0.15 suggestion floor)
        if suggestions.isEmpty {
            let heuristic = suggestConnections(for: item, maxResults: 5)
            suggestions = heuristic.filter { $0.score >= AppConstants.Scoring.autoConnectHeuristicFloor }
        }

        // Cap at 2 auto-connections
        let toCreate = Array(suggestions.prefix(AppConstants.Scoring.maxAutoConnections))
        for suggestion in toCreate {
            let connection = Connection(
                sourceItem: item,
                targetItem: suggestion.targetItem,
                type: suggestion.suggestedType
            )
            connection.isAutoGenerated = true
            modelContext.insert(connection)
        }

        if !toCreate.isEmpty {
            EntitlementService.shared.recordUse(.connectionSuggestions)
            try? modelContext.save()
        }
    }

    /// Query the LLM with a strict prompt that requires a confidence score.
    /// Only returns suggestions with score ≥ 0.7.
    private func autoConnectWithLLM(item: Item, candidates: [Item]) async -> [ConnectionSuggestion] {
        let systemPrompt = """
        You are a knowledge-management assistant. Given a source item and a list of candidates, \
        identify which candidates have a highly confident, meaningful connection to the source.

        Return a JSON object with:
        - "suggestions": an array of objects, each with:
          - "target_title": the exact title of the candidate item
          - "connection_type": one of "related", "contradicts", "buildsOn", "inspiredBy", "sameTopic"
          - "score": a confidence value from 0.0 to 1.0
          - "reason": a brief explanation (1 sentence, max 80 characters)

        Rules:
        - Only include connections where you are highly confident (score ≥ 0.7).
        - Prefer returning 0 suggestions over forcing weak connections.
        - Return an empty suggestions array if nothing meets this bar.
        - Only return valid JSON, no extra text.
        """

        let sourceDesc = LLMContextBuilder.itemDescription(item)
        let candidateList = LLMContextBuilder.itemList(Array(candidates.prefix(AppConstants.LLM.maxCandidateItems)))

        let userPrompt = """
        SOURCE ITEM:
        \(sourceDesc)

        CANDIDATE ITEMS:
        \(candidateList)
        """

        guard let result = await provider.complete(system: systemPrompt, user: userPrompt, service: "auto-connect") else {
            return []
        }

        guard let parsed = LLMJSONParser.decode(ConnectionSuggestionResponse.self, from: result.content) else {
            return []
        }

        let candidatesByTitle = Dictionary(
            candidates.map { ($0.title.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var suggestions: [ConnectionSuggestion] = []
        for entry in parsed.suggestions {
            let score = entry.score ?? 0.0
            guard score >= AppConstants.Scoring.autoConnectLLMConfidence else { continue }

            let normalizedTitle = entry.target_title.lowercased()
            guard let targetItem = candidatesByTitle[normalizedTitle],
                  targetItem.id != item.id else { continue }

            let connectionType = ConnectionType(rawValue: entry.connection_type) ?? .related
            let reason = String(entry.reason.prefix(AppConstants.LLM.reasonMaxLength))

            suggestions.append(ConnectionSuggestion(
                targetItem: targetItem,
                suggestedType: connectionType,
                score: score,
                reason: reason
            ))
        }

        return suggestions.sorted { $0.score > $1.score }
    }

    // MARK: - Dismissal Tracking

    /// Dismiss a suggestion so it won't recur for this item pair.
    func dismissSuggestion(sourceItemID: UUID, targetItemID: UUID) {
        var dismissed = Self.loadDismissed()
        let key = Self.pairKey(sourceItemID, targetItemID)
        dismissed[key] = Date()
        Self.saveDismissed(dismissed)
    }

    /// Record that a user frequently connects items — boost future suggestions
    /// involving items with similar tags. (Placeholder for future learning.)
    func recordAccepted(sourceItem: Item, targetItem: Item) {
        // Future: track accepted connection patterns to improve suggestions.
        // For now, the acceptance itself (creating the Connection) is enough signal.
    }

    // MARK: - Keyword Extraction

    private struct ItemKeywords {
        let titleWords: Set<String>
        let contentWords: Set<String>
    }

    private func extractKeywords(from item: Item) -> ItemKeywords {
        let titleWords = TextTokenizer.tokenize(item.title)

        var contentText = item.content ?? ""
        for reflection in item.reflections {
            contentText += " " + reflection.content
        }
        let contentWords = TextTokenizer.tokenize(contentText)

        return ItemKeywords(titleWords: titleWords, contentWords: contentWords)
    }

    // MARK: - Connection Type Inference

    private func inferConnectionType(sourceItem: Item, candidate: Item, sharedTagCount: Int) -> ConnectionType {
        // If they share many tags, likely same topic
        if sharedTagCount >= 3 {
            return .sameTopic
        }
        // If candidate is newer, it might build on source
        if candidate.createdAt > sourceItem.createdAt {
            return .buildsOn
        }
        // Default to related
        return .related
    }

    // MARK: - Persistence Helpers

    private static func pairKey(_ a: UUID, _ b: UUID) -> String {
        let sorted = [a.uuidString, b.uuidString].sorted()
        return "\(sorted[0])-\(sorted[1])"
    }

    private static func loadDismissed() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: dismissedKey),
              let dict = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func saveDismissed(_ dict: [String: Date]) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: dismissedKey)
        }
    }
}
