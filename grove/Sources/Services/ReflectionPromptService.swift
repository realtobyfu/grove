import Foundation
import SwiftData

/// A single AI-generated reflection prompt.
struct ReflectionPrompt: Identifiable {
    let id = UUID()
    let suggestedBlockType: ReflectionBlockType
    let text: String
}

/// LLM response shape for reflection prompts.
private struct ReflectionPromptResponse: Decodable {
    struct Prompt: Decodable {
        let block_type: String
        let text: String
    }
    let prompts: [Prompt]
}

/// Protocol for reflection prompt generation.
protocol ReflectionPromptServiceProtocol {
    @MainActor func generatePrompts(for item: Item, in context: ModelContext) async -> [ReflectionPrompt]
}

/// Generates contextual reflection prompts using the LLM.
/// Sends the current item's context plus related items and existing reflections
/// from the same board to produce personalized, wiki-link-enriched prompts.
/// Returns empty array on failure — never throws.
final class ReflectionPromptService: ReflectionPromptServiceProtocol {
    private let provider: LLMProvider

    init(provider: LLMProvider = LLMServiceConfig.makeProvider()) {
        self.provider = provider
    }

    @MainActor func generatePrompts(for item: Item, in context: ModelContext) async -> [ReflectionPrompt] {
        guard LLMServiceConfig.isConfigured else { return [] }
        guard EntitlementService.shared.canUse(.reflectionPrompts) else { return [] }

        // Only generate if the item has no existing reflections
        guard item.reflections.isEmpty else { return [] }

        // Gather related items from the same boards
        let boardItems = gatherBoardItems(for: item, in: context)

        // Gather connected items
        let connectedItems = gatherConnectedItems(for: item)

        let systemPrompt = """
        You are a knowledge-management assistant helping a user reflect on a saved item. \
        Generate 2-3 thought-provoking prompts that encourage deep engagement with the material.

        Return a JSON object with:
        - "prompts": an array of 2-3 objects, each with:
          - "block_type": one of "keyInsight", "connection", "disagreement"
          - "text": the prompt text (1-2 sentences, max 150 characters). \
            Reference the user's own items by name using [[Item Title]] wiki-link syntax when relevant.

        Rules:
        - Prompts should be specific to the item's content, not generic.
        - Reference the user's other items and reflections by title using [[wiki-links]] when meaningful.
        - Vary the block types — don't repeat the same type.
        - Prefer "connection" and "disagreement" types to encourage cross-pollination.
        - If the item has related items on the same board, prompt the user to compare or connect them.
        - Only return valid JSON, no extra text.
        """

        let contentExcerpt = String((item.content ?? "").prefix(1000))
        let tagNames = item.tags.map(\.name).joined(separator: ", ")

        var relatedContext = ""
        if !boardItems.isEmpty {
            let descriptions = LLMContextBuilder.itemList(Array(boardItems.prefix(10)), maxItems: 10)
            relatedContext = "\n\nRELATED ITEMS (same board):\n\(descriptions)"
        }

        var connectedContext = ""
        if !connectedItems.isEmpty {
            let descriptions = LLMContextBuilder.itemList(Array(connectedItems.prefix(5)), maxItems: 5)
            connectedContext = "\n\nCONNECTED ITEMS:\n\(descriptions)"
        }

        let userPrompt = """
        ITEM TO REFLECT ON:
        Title: \(item.title)
        Tags: \(tagNames.isEmpty ? "none" : tagNames)
        Content excerpt:
        \(contentExcerpt.isEmpty ? "(no content)" : contentExcerpt)\(relatedContext)\(connectedContext)
        """

        guard let result = await provider.complete(system: systemPrompt, user: userPrompt, service: "reflection_prompts") else {
            return []
        }

        guard let parsed = LLMJSONParser.decode(ReflectionPromptResponse.self, from: result.content) else {
            return []
        }

        let results = parsed.prompts.prefix(3).compactMap { entry -> ReflectionPrompt? in
            let blockType = ReflectionBlockType(rawValue: entry.block_type) ?? .keyInsight
            let text = String(entry.text.prefix(150))
            guard !text.isEmpty else { return nil }
            return ReflectionPrompt(suggestedBlockType: blockType, text: text)
        }

        if !results.isEmpty {
            EntitlementService.shared.recordUse(.reflectionPrompts)
        }

        return results
    }

    // MARK: - Context Gathering

    /// Gather other items from the same boards as the source item.
    private func gatherBoardItems(for item: Item, in context: ModelContext) -> [Item] {
        var boardItems: [Item] = []
        let seenIDs = Set([item.id])

        for board in item.boards {
            for boardItem in board.items {
                guard !seenIDs.contains(boardItem.id) else { continue }
                guard boardItem.id != item.id else { continue }
                boardItems.append(boardItem)
            }
        }

        // Sort by recency, most recent first
        boardItems.sort { $0.updatedAt > $1.updatedAt }
        return boardItems
    }

    /// Gather items connected to the source item.
    private func gatherConnectedItems(for item: Item) -> [Item] {
        var connected: [Item] = []
        for conn in item.outgoingConnections {
            if let target = conn.targetItem, target.id != item.id {
                connected.append(target)
            }
        }
        for conn in item.incomingConnections {
            if let source = conn.sourceItem, source.id != item.id {
                connected.append(source)
            }
        }
        return connected
    }
}
