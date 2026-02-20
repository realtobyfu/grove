import Foundation
import SwiftData
import Observation

// MARK: - Protocol

@MainActor protocol ConversationStarterServiceProtocol {
    var bubbles: [PromptBubble] { get }
    var isLoading: Bool { get }
    func refresh(items: [Item]) async
}

// MARK: - ConversationStarterService

/// Generates up to 3 contextual conversation starters for the HomeView prompt bubbles.
/// Uses a single LLM call with heuristic fallback when LLM is unavailable.
/// Results are persisted to UserDefaults (TTL: 8 hours) so they appear instantly on relaunch.
@MainActor @Observable final class ConversationStarterService: ConversationStarterServiceProtocol {

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
    }

    private static let maxBubbleCount = 3
    private static let cacheKey = "grove.conversationStarters"
    private static let cacheTTLSeconds: TimeInterval = 8 * 3600  // 8 hours

    init(provider: LLMProvider = LLMServiceConfig.makeProvider()) {
        self.provider = provider
        if let cached = Self.loadCachedBubbles() {
            self.bubbles = cached
        }
    }

    // MARK: - Public API

    /// Refreshes the prompt bubbles if not already loaded for this launch.
    /// Cached bubbles are shown immediately (from init); this replaces them with fresh ones.
    func refresh(items: [Item]) async {
        guard !hasLoaded else { return }
        hasLoaded = true

        let context = buildContext(from: items)

        // Attempt LLM generation, fall back to heuristics on failure
        if let llmBubbles = await generateViaLLM(context: context) {
            bubbles = llmBubbles
            Self.saveCachedBubbles(llmBubbles)
        } else {
            let heuristics = buildHeuristics(context: context)
            if !heuristics.isEmpty {
                bubbles = heuristics
                Self.saveCachedBubbles(heuristics)
            }
        }
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

    private func buildContext(from allItems: [Item]) -> StarterContext {
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3600)

        let recentItems = allItems.filter {
            ($0.status == .active || $0.status == .inbox) && $0.createdAt > sevenDaysAgo
        }

        let staleItems = allItems.filter {
            $0.status == .active &&
            $0.updatedAt < thirtyDaysAgo &&
            !$0.reflections.isEmpty
        }

        let contradictionItems = allItems.filter {
            $0.outgoingConnections.contains { $0.type == .contradicts }
        }

        // Top tag in recent items
        let recentTags = recentItems.flatMap { $0.tags.map(\.name) }
        let tagCounts = Dictionary(recentTags.map { ($0, 1) }, uniquingKeysWith: +)
        let topEntry = tagCounts.max(by: { $0.value < $1.value })

        // Unboarded cluster: items with no board assignment
        let unboardedCluster = findUnboardedCluster(from: allItems)

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
        guard !context.recentItems.isEmpty || !context.staleItems.isEmpty || !context.contradictionItems.isEmpty else {
            return nil
        }

        let systemPrompt = """
        You are a philosophical thinking partner that helps users reflect on their knowledge base.
        Given context about a user's recent notes, stale items, and contradictions, generate up to 3 engaging conversation starters.

        Rules:
        - Each starter is a single, thought-provoking question or prompt (1-2 sentences)
        - Tone: curious, intellectually engaged, not generic
        - Each starter has a short label: REVISIT, EXPLORE, RESOLVE, REFLECT, or SYNTHESIZE
        - Prioritize specificity — reference actual titles/topics from the context when possible
        - Return ONLY valid JSON. No markdown fences, no explanation.

        Output format:
        [{"prompt": "...", "label": "REVISIT"}, {"prompt": "...", "label": "EXPLORE"}]
        """

        var userLines: [String] = []

        if !context.staleItems.isEmpty {
            let titles = context.staleItems.prefix(3).map { "\"\($0.title)\"" }.joined(separator: ", ")
            userLines.append("Stale items not touched in 30+ days: \(titles)")
        }

        if !context.recentItems.isEmpty {
            let titles = context.recentItems.prefix(5).map { "\"\($0.title)\"" }.joined(separator: ", ")
            userLines.append("Recently saved items (last 7 days): \(titles)")
            if let tag = context.topRecentTag, context.topRecentTagCount >= 2 {
                userLines.append("Most frequent recent tag: \"\(tag)\" (\(context.topRecentTagCount) items)")
            }
        }

        if !context.contradictionItems.isEmpty {
            let titles = context.contradictionItems.prefix(2).map { "\"\($0.title)\"" }.joined(separator: " vs ")
            userLines.append("Items with contradictions: \(titles)")
        }

        if let cluster = context.unboardedCluster, !didShowClusterBubble {
            let titles = cluster.items.prefix(4).map { "\"\($0.title)\"" }.joined(separator: ", ")
            userLines.append("Unboarded items sharing tag \"\(cluster.sharedTag)\" (\(cluster.count) items): \(titles). If you generate a bubble for this, use label \"ORGANIZE\".")
            didShowClusterBubble = true
        }

        let userMessage = userLines.joined(separator: "\n")

        guard let result = await provider.complete(
            system: systemPrompt,
            user: userMessage,
            service: "conversationStarter"
        ) else {
            return nil
        }

        return parseLLMResponse(result.content)
    }

    // MARK: - Response Parsing

    private func parseLLMResponse(_ raw: String) -> [PromptBubble]? {
        // Strip markdown fences if present
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = cleaned.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return nil
        }

        let parsed = array.compactMap { dict -> PromptBubble? in
            guard let prompt = dict["prompt"], !prompt.isEmpty,
                  let label = dict["label"], !label.isEmpty else { return nil }
            return PromptBubble(prompt: prompt, label: label)
        }

        return parsed.isEmpty ? nil : Array(parsed.prefix(Self.maxBubbleCount))
    }

    // MARK: - Heuristic Fallback

    private func buildHeuristics(context: StarterContext) -> [PromptBubble] {
        var bubbles: [PromptBubble] = []

        // Stale high-value item
        if let stale = context.staleItems.first {
            bubbles.append(PromptBubble(
                prompt: "You haven't revisited \"\(stale.title)\" in over a month. What do you remember, and has your view changed?",
                label: "REVISIT"
            ))
        }

        // Recent tag cluster
        if let tag = context.topRecentTag, context.topRecentTagCount >= 2 {
            bubbles.append(PromptBubble(
                prompt: "You've saved \(context.topRecentTagCount) things about \"\(tag)\" recently. What's the central tension or open question?",
                label: "EXPLORE"
            ))
        }

        // Contradiction
        if !context.contradictionItems.isEmpty {
            bubbles.append(PromptBubble(
                prompt: "You have items that contradict each other. Want to work through the tension and find a synthesis?",
                label: "RESOLVE"
            ))
        }

        // Unboarded cluster — show at most once per launch
        if let cluster = context.unboardedCluster, !didShowClusterBubble, bubbles.count < Self.maxBubbleCount {
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

        return Array(bubbles.prefix(Self.maxBubbleCount))
    }

    // MARK: - Cache Helpers

    private static func saveCachedBubbles(_ bubbles: [PromptBubble]) {
        let encoded = bubbles.map {
            CachedBubble(prompt: $0.prompt, label: $0.label, clusterTag: $0.clusterTag, clusterItemIDs: $0.clusterItemIDs)
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
        return Array(
            cached
                .map { PromptBubble(prompt: $0.prompt, label: $0.label, clusterTag: $0.clusterTag, clusterItemIDs: $0.clusterItemIDs) }
                .prefix(Self.maxBubbleCount)
        )
    }
}
