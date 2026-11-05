import Foundation
import SwiftData

/// Local tool fulfillment for the agentic loop.
/// Queries SwiftData and returns formatted text strings for LLM context.
@MainActor
final class KnowledgeBaseTools {
    private let modelContext: ModelContext
    private let conversationID: UUID

    /// The board `create_board` proposed during this turn, if any.
    private(set) var boardProposal: BoardProposal?

    init(modelContext: ModelContext, conversationID: UUID) {
        self.modelContext = modelContext
        self.conversationID = conversationID
    }

    /// Dispatch a tool call by name. Returns the result string or nil if unknown tool.
    func fulfill(toolName: String, args: [String: String]) async -> String? {
        switch toolName {
        case "search_items":
            return await searchItems(query: args["query"] ?? "", limit: Int(args["limit"] ?? "5") ?? 5)
        case "get_item_detail":
            return getItemDetail(reference: args["id"] ?? args["item_id"] ?? args["title"] ?? "")
        case "get_reflections":
            return getReflections(reference: args["id"] ?? args["item_id"] ?? args["item_title"] ?? "")
        case "get_connections":
            return getConnections(reference: args["id"] ?? args["item_id"] ?? args["item_title"] ?? "")
        case "search_by_tag":
            return searchByTag(tagName: args["tag_name"] ?? "")
        case "get_board_items":
            return getBoardItems(boardName: args["board_name"] ?? "")
        case "create_board":
            return proposeBoard(
                boardName: args["board_name"] ?? "",
                itemReferences: (args["item_titles"] ?? "").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            )
        default:
            return nil
        }
    }

    /// Opening words of `toolDescriptions`, in every version a conversation may have stored.
    private static let toolDescriptionsMarker = "You have access to the user's knowledge base."

    /// Conversations keep the system prompt they started with, so older ones
    /// carry retired tool wording. The tool section is always the prompt's tail.
    static func withCurrentToolDescriptions(_ prompt: String) -> String {
        guard let marker = prompt.range(of: toolDescriptionsMarker) else { return prompt }
        return prompt[..<marker.lowerBound] + toolDescriptions
    }

    /// Available tool descriptions for the system prompt.
    static let toolDescriptions = """
    You have access to the user's knowledge base. To search or look up information, output a JSON object \
    with a "tool_call" key (and nothing else before or after it). Search results include each item's id — \
    prefer passing that id back to other tools instead of retyping the title. Available tools:

    {"tool_call": {"name": "search_items", "args": {"query": "search terms", "limit": "5"}}}
    Search items by meaning and keyword. Returns ids, titles, tags, and summaries.

    {"tool_call": {"name": "get_item_detail", "args": {"id": "item id or exact title"}}}
    Get full details for a specific item: content excerpt, tags, reflections, connections.

    {"tool_call": {"name": "get_reflections", "args": {"id": "item id or exact title"}}}
    Get all reflection blocks the user wrote on a specific item.

    {"tool_call": {"name": "get_connections", "args": {"id": "item id or exact title"}}}
    Get all connections (related, contradicts, builds-on, etc.) for an item.

    {"tool_call": {"name": "search_by_tag", "args": {"tag_name": "tag name"}}}
    Find all items that share a specific tag.

    {"tool_call": {"name": "get_board_items", "args": {"board_name": "Board Name"}}}
    List all items in a specific board/collection.

    {"tool_call": {"name": "create_board", "args": {"board_name": "New Board Name", "item_titles": "Title 1, Title 2, Title 3"}}}
    Propose a new board containing the listed items. item_titles is a comma-separated list of exact item titles. \
    This does not create the board: the user confirms it in the app and nothing is written until they do, so never \
    say the board exists. Use this when the user wants to organize a group of items into a new board.

    Only use tool calls when you need to look up specific information or propose a new board. Most of the time, \
    respond directly in conversational markdown.
    """

    /// Native tool specs for providers with API-level tool calling.
    /// Mirrors the prompt-based tools above.
    static let toolSpecs: [LLMToolSpec] = [
        LLMToolSpec(
            name: "search_items",
            description: "Search the user's knowledge base by meaning and keyword. Returns item ids, titles, tags, and summaries. Prefer passing returned ids to other tools.",
            parametersJSON: #"{"type":"object","properties":{"query":{"type":"string","description":"Search terms"},"limit":{"type":"integer","description":"Max results, default 5"}},"required":["query"]}"#
        ),
        LLMToolSpec(
            name: "get_item_detail",
            description: "Get full details for one item: content excerpt, tags, reflections, connections.",
            parametersJSON: #"{"type":"object","properties":{"id":{"type":"string","description":"Item id (preferred) or exact title"}},"required":["id"]}"#
        ),
        LLMToolSpec(
            name: "get_reflections",
            description: "Get all reflection blocks the user wrote on a specific item.",
            parametersJSON: #"{"type":"object","properties":{"id":{"type":"string","description":"Item id (preferred) or exact title"}},"required":["id"]}"#
        ),
        LLMToolSpec(
            name: "get_connections",
            description: "Get all connections (related, contradicts, builds-on, etc.) for an item.",
            parametersJSON: #"{"type":"object","properties":{"id":{"type":"string","description":"Item id (preferred) or exact title"}},"required":["id"]}"#
        ),
        LLMToolSpec(
            name: "search_by_tag",
            description: "Find all items that share a specific tag.",
            parametersJSON: #"{"type":"object","properties":{"tag_name":{"type":"string"}},"required":["tag_name"]}"#
        ),
        LLMToolSpec(
            name: "get_board_items",
            description: "List all items in a specific board/collection.",
            parametersJSON: #"{"type":"object","properties":{"board_name":{"type":"string"}},"required":["board_name"]}"#
        ),
        LLMToolSpec(
            name: "create_board",
            description: "Propose a new board containing the listed items. This does not create the board: the user confirms it in the app and nothing is written until they do, so never say the board exists. Use when the user wants to organize items into a new board.",
            parametersJSON: #"{"type":"object","properties":{"board_name":{"type":"string"},"item_titles":{"type":"string","description":"Comma-separated item ids or exact titles"}},"required":["board_name","item_titles"]}"#
        ),
    ]

    // MARK: - Tool Implementations

    private func searchItems(query: String, limit: Int) async -> String {
        let allItems = fetchAllItems()
        let queryLower = query.lowercased()

        let keywordMatches = allItems.filter { item in
            item.title.lowercased().contains(queryLower) ||
            (item.content ?? "").lowercased().contains(queryLower) ||
            item.tags.contains(where: { $0.name.lowercased().contains(queryLower) })
        }

        // Semantic matches from the embedding index, merged after keyword hits
        await EmbeddingIndexService.shared.indexItems(allItems.map(EmbeddingIndexService.snapshot))
        let semanticHits = await EmbeddingIndexService.shared.search(
            query: query,
            limit: limit,
            minScore: SearchViewModel.semanticScoreThreshold
        )
        let itemsByID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        let semanticMatches = semanticHits.compactMap { itemsByID[$0.id] }

        var seen = Set<UUID>()
        var merged: [Item] = []
        for item in keywordMatches + semanticMatches where seen.insert(item.id).inserted {
            merged.append(item)
        }
        let matches = merged.prefix(limit)

        if matches.isEmpty {
            return "No items found matching \"\(query)\"."
        }

        return matches.map { item in
            var line = "- \(item.title) (id: \(item.id.uuidString))"
            let tags = item.tags.map(\.name).joined(separator: ", ")
            if !tags.isEmpty { line += " [tags: \(tags)]" }
            if let summary = item.metadata["summary"], !summary.isEmpty {
                line += " — \(String(summary.prefix(120)))"
            }
            return line
        }.joined(separator: "\n")
    }

    private func getItemDetail(reference: String) -> String {
        guard let item = ItemResolver.resolve(reference, in: fetchAllItems()) else {
            return "Item \"\(reference)\" not found."
        }

        var result = "Title: \(item.title)\nID: \(item.id.uuidString)\nType: \(item.type.rawValue)\nStatus: \(item.status.rawValue)"
        let tags = item.tags.map(\.name).joined(separator: ", ")
        if !tags.isEmpty { result += "\nTags: \(tags)" }
        if let url = item.sourceURL { result += "\nSource: \(url)" }
        if let content = item.content {
            result += "\nContent excerpt: \(String(content.prefix(800)))"
        }

        if !item.reflections.isEmpty {
            result += "\n\nReflections:"
            for block in item.reflections.sorted(by: { $0.position < $1.position }) {
                result += "\n- [\(block.blockType.displayName)] \(String(block.content.prefix(200)))"
            }
        }

        let connections = item.outgoingConnections + item.incomingConnections
        if !connections.isEmpty {
            result += "\n\nConnections:"
            for conn in connections {
                let isOutgoing = conn.sourceItem?.id == item.id
                let other = isOutgoing ? conn.targetItem : conn.sourceItem
                result += "\n- \(conn.type.displayLabel(isOutgoing: isOutgoing)) → \(other?.title ?? "Unknown")"
            }
        }

        return result
    }

    private func getReflections(reference: String) -> String {
        guard let item = ItemResolver.resolve(reference, in: fetchAllItems()) else {
            return "Item \"\(reference)\" not found."
        }

        if item.reflections.isEmpty {
            return "No reflections found on \"\(item.title)\"."
        }

        return item.reflections.sorted(by: { $0.position < $1.position }).map { block in
            "[\(block.blockType.displayName)] \(block.content)"
        }.joined(separator: "\n\n")
    }

    private func getConnections(reference: String) -> String {
        guard let item = ItemResolver.resolve(reference, in: fetchAllItems()) else {
            return "Item \"\(reference)\" not found."
        }

        let connections = item.outgoingConnections + item.incomingConnections
        if connections.isEmpty {
            return "No connections found for \"\(item.title)\"."
        }

        return connections.map { conn in
            let isOutgoing = conn.sourceItem?.id == item.id
            let other = isOutgoing ? conn.targetItem : conn.sourceItem
            let direction = isOutgoing ? "→" : "←"
            var line = "\(conn.type.displayLabel(isOutgoing: isOutgoing)) \(direction) \(other?.title ?? "Unknown")"
            if let note = conn.note, !note.isEmpty {
                line += " (\(note))"
            }
            return line
        }.joined(separator: "\n")
    }

    private func searchByTag(tagName: String) -> String {
        let allItems = fetchAllItems()
        let tagLower = tagName.lowercased()

        let matches = allItems.filter { item in
            item.tags.contains(where: { $0.name.lowercased() == tagLower })
        }

        if matches.isEmpty {
            return "No items found with tag \"\(tagName)\"."
        }

        return "Items tagged \"\(tagName)\":\n" + matches.map { "- \(self.item($0))" }.joined(separator: "\n")
    }

    private func getBoardItems(boardName: String) -> String {
        let allBoards: [Board] = modelContext.fetchAll()
        guard let board = allBoards.first(where: { $0.title.lowercased() == boardName.lowercased() }) else {
            return "Board \"\(boardName)\" not found. Available boards: \(allBoards.map(\.title).joined(separator: ", "))"
        }

        if board.items.isEmpty {
            return "Board \"\(boardName)\" has no items."
        }

        return "Items in \"\(boardName)\":\n" + board.items.map { item in
            var line = "- \(item.title)"
            let tags = item.tags.map(\.name).joined(separator: ", ")
            if !tags.isEmpty { line += " [\(tags)]" }
            return line
        }.joined(separator: "\n")
    }

    /// Records a proposal for the user to confirm. Writes nothing.
    private func proposeBoard(boardName: String, itemReferences: [String]) -> String {
        let name = boardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return "Error: board_name is required."
        }

        let allBoards: [Board] = modelContext.fetchAll()
        // Avoid creating duplicate boards
        if allBoards.contains(where: { $0.title.lowercased() == name.lowercased() }) {
            return "Board \"\(name)\" already exists. Items were not reassigned."
        }

        let allItems = fetchAllItems()
        var matchedItems: [Item] = []
        var unmatchedTitles: [String] = []
        for reference in itemReferences {
            guard let item = ItemResolver.resolve(reference, in: allItems) else {
                unmatchedTitles.append(reference)
                continue
            }
            if !matchedItems.contains(where: { $0.id == item.id }) {
                matchedItems.append(item)
            }
        }

        boardProposal = BoardProposal(
            boardName: name,
            itemIDs: matchedItems.map(\.id),
            itemTitles: matchedItems.map(\.title),
            unmatchedTitles: unmatchedTitles,
            conversationID: conversationID
        )

        var result = "Board \"\(name)\" has NOT been created. It is waiting for the user's confirmation in the app. "
            + "Do not claim it exists; tell the user they can confirm it below."
        if !matchedItems.isEmpty {
            result += " Items it would contain: \(matchedItems.map(\.title).joined(separator: ", "))."
        }
        if !unmatchedTitles.isEmpty {
            result += " Not found: \(unmatchedTitles.joined(separator: ", "))."
        }
        return result
    }

    // MARK: - Helpers

    private func fetchAllItems() -> [Item] {
        modelContext.fetchAll()
    }

    private func item(_ item: Item) -> String {
        var line = item.title
        let tags = item.tags.map(\.name).joined(separator: ", ")
        if !tags.isEmpty { line += " [\(tags)]" }
        return line
    }
}
