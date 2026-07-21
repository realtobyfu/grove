import Foundation
import SwiftData

/// Local tool fulfillment for the agentic loop.
/// Queries SwiftData and returns formatted text strings for LLM context.
@MainActor
final class KnowledgeBaseTools {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
            return createBoard(
                boardName: args["board_name"] ?? "",
                itemTitles: (args["item_titles"] ?? "").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            )
        case "create_synthesis":
            return await createSynthesis(
                itemTitles: (args["item_titles"] ?? "").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                focusPrompt: args["focus_prompt"] ?? "",
                synthesisTitle: args["title"] ?? ""
            )
        default:
            return nil
        }
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
    Create a new board and assign the listed items to it. item_titles is a comma-separated list of exact item titles. \
    Use this when the user confirms they want to organize a group of items into a new board.

    {"tool_call": {"name": "create_synthesis", "args": {"item_titles": "Title 1, Title 2, Title 3", "focus_prompt": "What unifies these?", "title": "Synthesis: My Topic"}}}
    Generate a synthesis note from the listed items and save it as a new Item in the knowledge base. \
    item_titles is a comma-separated list of exact item titles (2-30 items required). \
    focus_prompt describes what angle or question the synthesis should address. \
    title is the title for the new synthesis item. \
    Use this when the user asks to synthesize, summarize across, or integrate multiple items. \
    Returns the created item's wiki-link, title, and ID.

    Only use tool calls when you need to look up specific information or perform a write action. Most of the time, \
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
            description: "Create a new board and assign the listed items to it. Use when the user confirms they want to organize items into a new board.",
            parametersJSON: #"{"type":"object","properties":{"board_name":{"type":"string"},"item_titles":{"type":"string","description":"Comma-separated item ids or exact titles"}},"required":["board_name","item_titles"]}"#
        ),
        LLMToolSpec(
            name: "create_synthesis",
            description: "Generate a synthesis note from 2-30 items and save it as a new item. Use when the user asks to synthesize, summarize across, or integrate multiple items. Returns the created item's wiki-link, title, and id.",
            parametersJSON: #"{"type":"object","properties":{"item_titles":{"type":"string","description":"Comma-separated item ids or exact titles (2-30)"},"focus_prompt":{"type":"string","description":"What angle or question the synthesis should address"},"title":{"type":"string","description":"Title for the new synthesis item"}},"required":["item_titles"]}"#
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
        let semanticHits = await EmbeddingIndexService.shared.search(query: query, limit: limit)
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
                result += "\n- \(conn.type.displayLabel) → \(other?.title ?? "Unknown")"
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
            var line = "\(conn.type.displayLabel) \(direction) \(other?.title ?? "Unknown")"
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

    private func createBoard(boardName: String, itemTitles: [String]) -> String {
        guard !boardName.isEmpty else {
            return "Error: board_name is required."
        }

        let allBoards: [Board] = modelContext.fetchAll()
        // Avoid creating duplicate boards
        if allBoards.contains(where: { $0.title.lowercased() == boardName.lowercased() }) {
            return "Board \"\(boardName)\" already exists. Items were not reassigned."
        }

        let board = Board(title: boardName)
        modelContext.insert(board)

        // Assign listed items to the new board
        let allItems = fetchAllItems()
        var assignedTitles: [String] = []
        for title in itemTitles {
            if let item = ItemResolver.resolve(title, in: allItems) {
                item.boards.append(board)
                board.items.append(item)
                assignedTitles.append(item.title)
            }
        }

        try? modelContext.save()

        if assignedTitles.isEmpty {
            return "Board \"\(boardName)\" created with no items (none of the specified titles matched)."
        }

        return "Board \"\(boardName)\" created and \(assignedTitles.count) item(s) assigned: \(assignedTitles.joined(separator: ", "))."
    }

    private func createSynthesis(itemTitles: [String], focusPrompt: String, synthesisTitle: String) async -> String {
        guard itemTitles.count >= AppConstants.Activity.synthesisMinItems else {
            return "Error: create_synthesis requires at least \(AppConstants.Activity.synthesisMinItems) item titles. Got \(itemTitles.count)."
        }
        guard itemTitles.count <= AppConstants.Activity.synthesisMaxItems else {
            return "Error: Too many items (\(itemTitles.count)). Synthesis works best with \(AppConstants.Activity.synthesisMinItems)-\(AppConstants.Activity.synthesisMaxItems) items."
        }

        let allItems = fetchAllItems()
        var matchedItems: [Item] = []
        var missingTitles: [String] = []
        for title in itemTitles {
            if let item = ItemResolver.resolve(title, in: allItems) {
                matchedItems.append(item)
            } else {
                missingTitles.append(title)
            }
        }

        guard matchedItems.count >= AppConstants.Activity.synthesisMinItems else {
            return "Error: Could not find enough matching items. Missing: \(missingTitles.joined(separator: ", ")). Found: \(matchedItems.map(\.title).joined(separator: ", "))."
        }

        let scopeTitle = focusPrompt.isEmpty ? synthesisTitle : focusPrompt
        let resolvedTitle = synthesisTitle.isEmpty ? "Synthesis: \(scopeTitle)" : synthesisTitle

        let service = SynthesisService(modelContext: modelContext)
        guard let result = await service.generateSynthesis(items: matchedItems, scopeTitle: scopeTitle) else {
            return "Error: Synthesis generation failed."
        }

        let newItem = service.createSynthesisItem(from: result, title: resolvedTitle, inBoard: nil)

        var response = "Synthesis note created: [[\(newItem.title)]] (ID: \(newItem.id.uuidString))\n"
        response += "Sources: \(matchedItems.map { "[[\($0.title)]]" }.joined(separator: ", "))\n"
        if !missingTitles.isEmpty {
            response += "Note: \(missingTitles.count) item(s) not found and skipped: \(missingTitles.joined(separator: ", "))."
        }
        return response
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
