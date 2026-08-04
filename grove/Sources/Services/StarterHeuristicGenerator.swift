import Foundation

// MARK: - StarterHeuristicGenerator

/// Generates heuristic (non-LLM) conversation starter bubbles for board
/// surfaces, where a starter is always worth showing. Home no longer has a
/// heuristic path — its starters are LLM-or-nothing.
enum StarterHeuristicGenerator {

    /// Maximum bubble count for Pro users (used to cap output).
    private static let maxBubbleCountPro = 3

    // MARK: - Board-Scoped Heuristics

    /// Board-scoped heuristics — uses the same StarterContext but skips unboarded-cluster logic.
    @MainActor
    static func buildBoardHeuristics(context: StarterContext, boardID: UUID) -> [PromptBubble] {
        var bubbles: [PromptBubble] = []

        // Stale high-value item in this board
        if let stale = context.staleItems.first {
            let title = StarterLLMGenerator.trimmedTitle(stale.title)
            let framing = stale.type == .note
                ? "You haven't revisited your note \"\(title)\" in a while. Has your thinking changed?"
                : "You haven't revisited \"\(title)\" in a while. What do you remember?"
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

        // Contradiction — prefer a concrete pair with its specific tension reason
        if let pair = context.contradictionPairs.first {
            let pairItems = [pair.source, pair.target]
            let source = StarterLLMGenerator.trimmedTitle(pair.source.title)
            let target = StarterLLMGenerator.trimmedTitle(pair.target.title)
            let prompt: String
            if let reason = pair.reason {
                prompt = "\"\(source)\" and \"\(target)\" are in tension: \(reason) Want to work through it?"
            } else {
                prompt = "\"\(source)\" and \"\(target)\" seem to disagree. Want to work through the tension?"
            }
            bubbles.append(PromptBubble(
                prompt: prompt,
                label: "RESOLVE",
                clusterItemIDs: pairItems.map(\.id),
                boardIDs: [boardID]
            ))
        }

        // Board-level fallback
        if bubbles.isEmpty, let first = context.recentItems.first {
            bubbles.append(PromptBubble(
                prompt: "What stands out most to you about \"\(StarterLLMGenerator.trimmedTitle(first.title))\"?",
                label: "REFLECT",
                clusterItemIDs: [first.id],
                boardIDs: [boardID]
            ))
        }

        return Array(bubbles.prefix(maxBubbleCountPro))
    }
}
