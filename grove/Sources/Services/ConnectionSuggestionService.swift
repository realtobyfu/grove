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

    init(modelContext: ModelContext, provider: LLMProvider = GroqProvider()) {
        self.modelContext = modelContext
        self.provider = provider
    }

    // MARK: - LLM-Backed Suggestions (Primary)

    /// Suggest connections using the LLM. Falls back to heuristic method if LLM fails.
    /// Call this from async contexts (Task blocks) for best results.
    func suggestConnectionsAsync(for sourceItem: Item, maxResults: Int = 3) async -> [ConnectionSuggestion] {
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
                    return llmSuggestions
                }
            }
        }

        // Fallback to heuristic
        return suggestConnections(for: sourceItem, maxResults: maxResults)
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

        let sourceTagNames = sourceItem.tags.map(\.name).joined(separator: ", ")
        let sourceReflections = sourceItem.reflections
            .sorted { $0.position < $1.position }
            .prefix(5)
            .map { "\($0.blockType.displayName): \($0.content)" }
            .joined(separator: "\n")
        let contentExcerpt = String((sourceItem.content ?? "").prefix(1000))

        var candidateDescriptions: [String] = []
        for (index, candidate) in candidates.prefix(50).enumerated() {
            let tags = candidate.tags.map(\.name).joined(separator: ", ")
            let summary = candidate.metadata["summary"] ?? ""
            let line = "\(index + 1). \"\(candidate.title)\" [tags: \(tags.isEmpty ? "none" : tags)]\(summary.isEmpty ? "" : " — \(summary)")"
            candidateDescriptions.append(line)
        }

        let userPrompt = """
        SOURCE ITEM:
        Title: \(sourceItem.title)
        Tags: \(sourceTagNames.isEmpty ? "none" : sourceTagNames)
        Content excerpt:
        \(contentExcerpt.isEmpty ? "(no content)" : contentExcerpt)
        \(sourceReflections.isEmpty ? "" : "Reflections:\n\(sourceReflections)")

        CANDIDATE ITEMS:
        \(candidateDescriptions.joined(separator: "\n"))
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
            let reason = String(entry.reason.prefix(80))

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
            let titleSim = jaccardSimilarity(sourceWords.titleWords, candidateWords.titleWords)
            if titleSim > 0.1 {
                totalScore += titleSim * 0.4
                reasons.append("similar titles")
            }

            // 3. Content keyword overlap
            let contentSim = jaccardSimilarity(sourceWords.contentWords, candidateWords.contentWords)
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
            guard totalScore >= 0.15 else { continue }

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
        let titleWords = tokenize(item.title)

        var contentText = item.content ?? ""
        // Include annotation content for richer signal
        for annotation in item.annotations {
            contentText += " " + annotation.content
        }
        // Include reflection content for richer signal
        for reflection in item.reflections {
            contentText += " " + reflection.content
        }
        let contentWords = tokenize(contentText)

        return ItemKeywords(titleWords: titleWords, contentWords: contentWords)
    }

    private func tokenize(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let cleaned = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }
        let words = String(cleaned)
            .components(separatedBy: .whitespaces)
            .filter { $0.count >= 3 }  // Skip very short words
        // Remove common stop words
        let stopWords: Set<String> = [
            "the", "and", "for", "are", "but", "not", "you", "all",
            "can", "had", "her", "was", "one", "our", "out", "has",
            "its", "let", "say", "she", "too", "use", "way", "who",
            "how", "man", "did", "get", "may", "him", "old", "see",
            "now", "any", "new", "also", "back", "been", "come",
            "each", "from", "have", "here", "just", "know", "like",
            "make", "many", "more", "much", "must", "name", "over",
            "only", "some", "such", "take", "than", "that", "them",
            "then", "they", "this", "very", "when", "what", "will",
            "with", "your", "into", "about", "could", "other",
            "their", "there", "these", "those", "which", "would",
        ]
        return Set(words).subtracting(stopWords)
    }

    private func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
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
