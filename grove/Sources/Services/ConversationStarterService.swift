import Foundation
import SwiftData
import Observation

// MARK: - Protocol

@MainActor protocol ConversationStarterServiceProtocol {
    var bubbles: [PromptBubble] { get }
    var isLoading: Bool { get }
    func refresh(items: [Item]) async
    func forceRefresh(items: [Item]) async
    func bubbles(for boardID: UUID, maxResults: Int) -> [PromptBubble]
}

// MARK: - ConversationStarterService

/// Generates up to 3 contextual conversation starters for the HomeView prompt bubbles.
/// Uses a single LLM call with heuristic fallback when LLM is unavailable.
/// Results are persisted to UserDefaults (TTL: 8 hours) so they appear instantly on relaunch.
@MainActor @Observable final class ConversationStarterService: ConversationStarterServiceProtocol {
    static let shared = ConversationStarterService()

    private(set) var bubbles: [PromptBubble] = []
    private(set) var isLoading: Bool = false

    /// Whether this service has fetched starters for the current launch.
    private var hasLoaded: Bool = false
    /// Track if we already showed the unboarded-cluster bubble this launch (show at most once).
    private var didShowClusterBubble: Bool = false

    private let provider: LLMProvider

    // MARK: - Disk Cache

    private struct CachedBubble: Codable {
        let prompt: String
        let label: String
        let clusterTag: String?
        let clusterItemIDs: [UUID]
        let boardIDs: [UUID]?
    }

    private static let maxBubbleCountPro = 3
    private static let maxBubbleCountFree = 2
    private static let cacheKey = "grove.conversationStarters"
    private static let cacheTTLSeconds: TimeInterval = 8 * 3600  // 8 hours

    private static var maxBubbleCount: Int {
        EntitlementService.currentTier == .pro ? maxBubbleCountPro : maxBubbleCountFree
    }

    init(provider: LLMProvider = LLMServiceConfig.makeProvider()) {
        self.provider = provider
        // Only load cache for Pro users — prevents stale Pro bubbles showing after downgrade
        if EntitlementService.currentTier == .pro, let cached = Self.loadCachedBubbles() {
            self.bubbles = cached
        }
    }

    // MARK: - Public API

    /// Refreshes the prompt bubbles if not already loaded for this launch.
    /// Cached bubbles are shown immediately (from init); this replaces them with fresh ones.
    func refresh(items: [Item]) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }

        let context = buildContext(from: items)
        let isPro = await EntitlementService.shared.isPro
        let cap = isPro ? Self.maxBubbleCountPro : Self.maxBubbleCountFree

        if isPro {
            // Pro: attempt full LLM generation, fall back to heuristics
            if let llmBubbles = await generateViaLLM(context: context) {
                bubbles = Array(llmBubbles.prefix(cap))
                Self.saveCachedBubbles(bubbles)
            } else {
                let heuristics = buildHeuristics(context: context)
                if !heuristics.isEmpty {
                    bubbles = Array(heuristics.prefix(cap))
                    Self.saveCachedBubbles(bubbles)
                }
            }
        } else {
            // Free: attempt 1 LLM bubble, always include 1 heuristic fallback
            let heuristics = buildHeuristics(context: context)
            if let llmBubbles = await generateViaLLM(context: context), let first = llmBubbles.first {
                var result = [first]
                if let heuristic = heuristics.first(where: { $0.prompt != first.prompt }) {
                    result.append(heuristic)
                } else if heuristics.count > 1 {
                    result.append(heuristics[1])
                } else if let fallback = heuristics.first {
                    result.append(fallback)
                }
                bubbles = Array(result.prefix(cap))
            } else {
                bubbles = Array(heuristics.prefix(cap))
            }
            Self.saveCachedBubbles(bubbles)
        }
    }

    func forceRefresh(items: [Item]) async {
        hasLoaded = false
        await refresh(items: items)
    }

    func bubbles(for boardID: UUID, maxResults: Int) -> [PromptBubble] {
        guard maxResults > 0 else { return [] }
        return Array(
            bubbles
                .filter { $0.boardIDs.contains(boardID) }
                .prefix(maxResults)
        )
    }

    // MARK: - Context Building

    private struct StarterContext {
        let recentItems: [Item]          // last 7 days
        let staleItems: [Item]           // untouched 30+ days with reflections
        let contradictionItems: [Item]   // items with .contradicts outgoing connections
        let topRecentTag: String?
        let topRecentTagCount: Int
        let unboardedCluster: UnboardedCluster?  // cluster of unboarded items sharing tags
    }

    struct UnboardedCluster {
        let sharedTag: String
        let items: [Item]
        let count: Int
    }

    private struct LLMContextCandidate {
        let id: String
        let summary: String
        let clusterTag: String?
        let itemIDs: [UUID]
        let boardIDs: [UUID]
    }

    private func buildContext(from allItems: [Item]) -> StarterContext {
        let suggestionEligibleItems = allItems.filter { $0.isIncludedInDiscussionSuggestions }
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3600)

        let recentItems = suggestionEligibleItems.filter {
            ($0.status == .active || $0.status == .inbox) && $0.createdAt > sevenDaysAgo
        }

        let staleItems = suggestionEligibleItems.filter {
            $0.status == .active &&
            $0.updatedAt < thirtyDaysAgo &&
            !$0.reflections.isEmpty
        }

        let contradictionItems = suggestionEligibleItems.filter {
            $0.outgoingConnections.contains { $0.type == .contradicts }
        }

        // Top tag in recent items
        let recentTags = recentItems.flatMap { $0.tags.map(\.name) }
        let tagCounts = Dictionary(recentTags.map { ($0, 1) }, uniquingKeysWith: +)
        let topEntry = tagCounts.max(by: { $0.value < $1.value })

        // Unboarded cluster: items with no board assignment
        let unboardedCluster = findUnboardedCluster(from: suggestionEligibleItems)

        return StarterContext(
            recentItems: recentItems,
            staleItems: staleItems,
            contradictionItems: contradictionItems,
            topRecentTag: topEntry?.key,
            topRecentTagCount: topEntry?.value ?? 0,
            unboardedCluster: unboardedCluster
        )
    }

    /// Finds a cluster of unboarded items sharing 2+ tags, with at least 4 items total.
    /// Returns the largest such cluster, keyed on the most-shared tag.
    private func findUnboardedCluster(from allItems: [Item]) -> UnboardedCluster? {
        let unboarded = allItems.filter { $0.boards.isEmpty && ($0.status == .active || $0.status == .inbox) }
        guard unboarded.count >= 4 else { return nil }

        // Count how many unboarded items share each tag
        let tagGroups = Dictionary(grouping: unboarded.flatMap { item in
            item.tags.map { tag in (tag.name, item) }
        }, by: { $0.0 })

        // Find the tag with the most unboarded items (at least 4 items)
        let bestEntry = tagGroups
            .filter { $0.value.count >= 4 }
            .max(by: { $0.value.count < $1.value.count })

        guard let (tag, pairs) = bestEntry else { return nil }

        // Require that at least 2 distinct tags are shared across these items (quality check)
        let clusterItems = pairs.map(\.1)
        let sharedTagNames = Set(clusterItems.flatMap { $0.tags.map(\.name) })
        guard sharedTagNames.count >= 2 else { return nil }

        return UnboardedCluster(sharedTag: tag, items: clusterItems, count: clusterItems.count)
    }

    // MARK: - LLM Generation

    private func generateViaLLM(context: StarterContext) async -> [PromptBubble]? {
        let candidates = llmContextCandidates(from: context)
        guard !candidates.isEmpty else {
            return nil
        }

        let systemPrompt = """
        You are a philosophical thinking partner that helps users reflect on their knowledge base.
        Given context snippets, generate up to 3 engaging conversation starters.

        Rules:
        - Each starter is a single, thought-provoking question or prompt (1-2 sentences)
        - Tone: curious, intellectually engaged, not generic
        - Each starter has a short label: REVISIT, EXPLORE, RESOLVE, REFLECT, SYNTHESIZE, or ORGANIZE
        - If a starter is tied to one of the snippets below, include its exact `context_id`
        - If a starter is general and not tied to a specific snippet, use `context_id` = "general"
        - Return ONLY valid JSON. No markdown fences, no explanation.

        Output format:
        [{"prompt": "...", "label": "REVISIT", "context_id": "stale_0"}]
        """

        var userLines: [String] = ["Context snippets (with stable IDs):"]
        userLines.append(contentsOf: candidates.map { "- \($0.id): \($0.summary)" })
        let userMessage = userLines.joined(separator: "\n")

        guard let result = await provider.complete(
            system: systemPrompt,
            user: userMessage,
            service: "conversationStarter"
        ) else {
            return nil
        }

        let parsed = parseLLMResponse(result.content, candidates: candidates)
        if parsed?.contains(where: { $0.clusterTag != nil }) == true {
            didShowClusterBubble = true
        }
        return parsed
    }

    // MARK: - Response Parsing

    private struct LLMBubblePayload: Decodable {
        let prompt: String
        let label: String
        let contextID: String?

        private enum CodingKeys: String, CodingKey {
            case prompt
            case label
            case contextID = "context_id"
        }
    }

    private func parseLLMResponse(_ raw: String, candidates: [LLMContextCandidate]) -> [PromptBubble]? {
        // Strip markdown fences if present
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = cleaned.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([LLMBubblePayload].self, from: data) else {
            return nil
        }

        let candidateLookup = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })

        let parsed = decoded.compactMap { payload -> PromptBubble? in
            let prompt = payload.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = payload.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, !label.isEmpty else { return nil }

            let candidate = payload.contextID.flatMap { candidateLookup[$0] }
            return PromptBubble(
                prompt: prompt,
                label: label,
                clusterTag: candidate?.clusterTag,
                clusterItemIDs: candidate?.itemIDs ?? [],
                boardIDs: candidate?.boardIDs ?? []
            )
        }

        return parsed.isEmpty ? nil : Array(parsed.prefix(Self.maxBubbleCountPro))
    }

    // MARK: - Heuristic Fallback

    private func buildHeuristics(context: StarterContext) -> [PromptBubble] {
        var bubbles: [PromptBubble] = []

        // Stale high-value item
        if let stale = context.staleItems.first {
            bubbles.append(PromptBubble(
                prompt: "You haven't revisited \"\(stale.title)\" in over a month. What do you remember, and has your view changed?",
                label: "REVISIT",
                clusterItemIDs: [stale.id],
                boardIDs: boardIDs(for: [stale])
            ))
        }

        // Recent tag cluster
        if let tag = context.topRecentTag, context.topRecentTagCount >= 2 {
            let relatedRecentItems = context.recentItems
                .filter { item in item.tags.contains(where: { $0.name == tag }) }
                .prefix(6)
            let relatedRecentArray = Array(relatedRecentItems)
            bubbles.append(PromptBubble(
                prompt: "You've saved \(context.topRecentTagCount) things about \"\(tag)\" recently. What's the central tension or open question?",
                label: "EXPLORE",
                clusterItemIDs: relatedRecentArray.map(\.id),
                boardIDs: boardIDs(for: relatedRecentArray)
            ))
        }

        // Contradiction
        if !context.contradictionItems.isEmpty {
            let relatedContradictions = Array(context.contradictionItems.prefix(2))
            bubbles.append(PromptBubble(
                prompt: "You have items that contradict each other. Want to work through the tension and find a synthesis?",
                label: "RESOLVE",
                clusterItemIDs: relatedContradictions.map(\.id),
                boardIDs: boardIDs(for: relatedContradictions)
            ))
        }

        // Unboarded cluster — show at most once per launch
        if let cluster = context.unboardedCluster, !didShowClusterBubble, bubbles.count < Self.maxBubbleCountPro {
            bubbles.append(PromptBubble(
                prompt: "You have \(cluster.count) items about \"\(cluster.sharedTag)\" floating around without a board. Want to organize them?",
                label: "ORGANIZE",
                clusterTag: cluster.sharedTag,
                clusterItemIDs: cluster.items.map(\.id)
            ))
            didShowClusterBubble = true
        }

        // Keep Home decision-light but never empty: always provide one meaningful fallback.
        if bubbles.isEmpty {
            bubbles.append(PromptBubble(
                prompt: "What question feels most worth thinking through right now?",
                label: "REFLECT"
            ))
        }

        return Array(bubbles.prefix(Self.maxBubbleCountPro))
    }

    private func llmContextCandidates(from context: StarterContext) -> [LLMContextCandidate] {
        var candidates: [LLMContextCandidate] = []

        if !context.recentItems.isEmpty {
            let recentItems = Array(context.recentItems.prefix(6))
            let titles = recentItems.prefix(4).map { "\"\($0.title)\"" }.joined(separator: ", ")
            candidates.append(LLMContextCandidate(
                id: "recent_items",
                summary: "Recently saved items (last 7 days): \(titles)",
                clusterTag: nil,
                itemIDs: recentItems.map(\.id),
                boardIDs: boardIDs(for: recentItems)
            ))
        }

        for (index, item) in context.staleItems.prefix(2).enumerated() {
            candidates.append(LLMContextCandidate(
                id: "stale_\(index)",
                summary: "Stale item not touched in 30+ days: \"\(item.title)\"",
                clusterTag: nil,
                itemIDs: [item.id],
                boardIDs: boardIDs(for: [item])
            ))
        }

        if let tag = context.topRecentTag, context.topRecentTagCount >= 2 {
            let recentTaggedItems = Array(
                context.recentItems
                    .filter { item in item.tags.contains(where: { $0.name == tag }) }
                    .prefix(6)
            )
            if !recentTaggedItems.isEmpty {
                let titles = recentTaggedItems.prefix(4).map { "\"\($0.title)\"" }.joined(separator: ", ")
                candidates.append(LLMContextCandidate(
                    id: "recent_tag",
                    summary: "Recent cluster for tag \"\(tag)\" (\(context.topRecentTagCount) items): \(titles)",
                    clusterTag: nil,
                    itemIDs: recentTaggedItems.map(\.id),
                    boardIDs: boardIDs(for: recentTaggedItems)
                ))
            }
        }

        let contradictionItems = Array(context.contradictionItems.prefix(2))
        if !contradictionItems.isEmpty {
            let titles = contradictionItems.map { "\"\($0.title)\"" }.joined(separator: " vs ")
            candidates.append(LLMContextCandidate(
                id: "contradiction",
                summary: "Items with contradictions: \(titles)",
                clusterTag: nil,
                itemIDs: contradictionItems.map(\.id),
                boardIDs: boardIDs(for: contradictionItems)
            ))
        }

        if let cluster = context.unboardedCluster, !didShowClusterBubble {
            let titles = cluster.items.prefix(4).map { "\"\($0.title)\"" }.joined(separator: ", ")
            candidates.append(LLMContextCandidate(
                id: "organize_cluster",
                summary: "Unboarded items sharing tag \"\(cluster.sharedTag)\" (\(cluster.count) items): \(titles)",
                clusterTag: cluster.sharedTag,
                itemIDs: cluster.items.map(\.id),
                boardIDs: []
            ))
        }

        return candidates
    }

    private func boardIDs(for items: [Item]) -> [UUID] {
        let ids = items.flatMap { $0.boards.map(\.id) }
        let unique = Set(ids)
        return unique.sorted { $0.uuidString < $1.uuidString }
    }

    // MARK: - Cache Helpers

    private static func saveCachedBubbles(_ bubbles: [PromptBubble]) {
        let encoded = bubbles.map {
            CachedBubble(
                prompt: $0.prompt,
                label: $0.label,
                clusterTag: $0.clusterTag,
                clusterItemIDs: $0.clusterItemIDs,
                boardIDs: $0.boardIDs
            )
        }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        let entry: [String: Any] = ["data": data, "timestamp": Date().timeIntervalSince1970]
        UserDefaults.standard.set(entry, forKey: cacheKey)
    }

    private static func loadCachedBubbles() -> [PromptBubble]? {
        guard let entry = UserDefaults.standard.dictionary(forKey: cacheKey),
              let data = entry["data"] as? Data,
              let timestamp = entry["timestamp"] as? TimeInterval else { return nil }

        let age = Date().timeIntervalSince1970 - timestamp
        guard age < cacheTTLSeconds else { return nil }

        guard let cached = try? JSONDecoder().decode([CachedBubble].self, from: data) else { return nil }
        let cap = maxBubbleCount
        return Array(
            cached
                .map {
                    PromptBubble(
                        prompt: $0.prompt,
                        label: $0.label,
                        clusterTag: $0.clusterTag,
                        clusterItemIDs: $0.clusterItemIDs,
                        boardIDs: $0.boardIDs ?? []
                    )
                }
                .prefix(cap)
        )
    }
}
