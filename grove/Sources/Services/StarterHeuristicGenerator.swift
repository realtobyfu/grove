import Foundation

// MARK: - StarterHeuristicGenerator

/// Generates heuristic (non-LLM) conversation starter bubbles as a fallback
/// when the LLM is unavailable or for free-tier users.
enum StarterHeuristicGenerator {

    /// Maximum bubble count for Pro users (used to cap output).
    private static let maxBubbleCountPro = 3

    // MARK: - Global Heuristics

    /// Builds heuristic conversation starters from the given context.
    /// Always returns at least one bubble (a generic fallback).
    @MainActor
    static func buildHeuristics(
        context: StarterContext,
        didShowClusterBubble: Bool
    ) -> [PromptBubble] {
        var bubbles: [PromptBubble] = []

        // Stale high-value item
        if let stale = context.staleItems.first {
            let staleFraming = stale.type == .note
                ? "You haven't revisited your note \"\(stale.title)\" in over a month. What do you remember, and has your view changed?"
                : "You haven't revisited \"\(stale.title)\" in over a month. What do you remember, and has your view changed?"
            bubbles.append(PromptBubble(
                prompt: staleFraming,
                label: "REVISIT",
                clusterItemIDs: [stale.id],
                boardIDs: StarterContextBuilder.boardIDs(for: [stale])
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
                boardIDs: StarterContextBuilder.boardIDs(for: relatedRecentArray)
            ))
        }

        // Contradiction
        if !context.contradictionItems.isEmpty {
            let relatedContradictions = Array(context.contradictionItems.prefix(2))
            bubbles.append(PromptBubble(
                prompt: "You have items that contradict each other. Want to work through the tension and find a synthesis?",
                label: "RESOLVE",
                clusterItemIDs: relatedContradictions.map(\.id),
                boardIDs: StarterContextBuilder.boardIDs(for: relatedContradictions)
            ))
        }

        // Unboarded cluster — show at most once per launch
        if let cluster = context.unboardedCluster, !didShowClusterBubble, bubbles.count < maxBubbleCountPro {
            bubbles.append(PromptBubble(
                prompt: "You have \(cluster.count) items about \"\(cluster.sharedTag)\" floating around without a board. Want to organize them?",
                label: "ORGANIZE",
                clusterTag: cluster.sharedTag,
                clusterItemIDs: cluster.items.map(\.id)
            ))
        }

        // Keep Home decision-light but never empty: always provide one meaningful fallback.
        if bubbles.isEmpty {
            bubbles.append(PromptBubble(
                prompt: "What question feels most worth thinking through right now?",
                label: "REFLECT"
            ))
        }

        return Array(bubbles.prefix(maxBubbleCountPro))
    }

    // MARK: - Board-Scoped Heuristics

    /// Board-scoped heuristics — uses the same StarterContext but skips unboarded-cluster logic.
    @MainActor
    static func buildBoardHeuristics(context: StarterContext, boardID: UUID) -> [PromptBubble] {
        var bubbles: [PromptBubble] = []

        // Stale high-value item in this board
        if let stale = context.staleItems.first {
            let framing = stale.type == .note
                ? "You haven't revisited your note \"\(stale.title)\" in a while. Has your thinking changed?"
                : "You haven't revisited \"\(stale.title)\" in a while. What do you remember?"
            bubbles.append(PromptBubble(
                prompt: framing,
                label: "REVISIT",
                clusterItemIDs: [stale.id],
                boardIDs: [boardID]
            ))
        }

        // Tag cluster within this board
        if let tag = context.topRecentTag, context.topRecentTagCount >= 2 {
            let relatedItems = Array(context.recentItems
                .filter { item in item.tags.contains(where: { $0.name == tag }) }
                .prefix(6))
            bubbles.append(PromptBubble(
                prompt: "You've been collecting items about \"\(tag)\". What's the thread connecting them?",
                label: "EXPLORE",
                clusterItemIDs: relatedItems.map(\.id),
                boardIDs: [boardID]
            ))
        }

        // Contradiction
        if !context.contradictionItems.isEmpty {
            let items = Array(context.contradictionItems.prefix(2))
            bubbles.append(PromptBubble(
                prompt: "Some items here seem to disagree. Want to work through the tension?",
                label: "RESOLVE",
                clusterItemIDs: items.map(\.id),
                boardIDs: [boardID]
            ))
        }

        // Board-level fallback
        if bubbles.isEmpty, let first = context.recentItems.first {
            bubbles.append(PromptBubble(
                prompt: "What stands out most to you about \"\(first.title)\"?",
                label: "REFLECT",
                clusterItemIDs: [first.id],
                boardIDs: [boardID]
            ))
        }

        return Array(bubbles.prefix(maxBubbleCountPro))
    }
}
