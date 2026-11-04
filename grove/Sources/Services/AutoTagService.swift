import Foundation
import SQLiteData

extension Notification.Name {
    /// Posted after auto-tagging when a new board should be suggested to the user.
    /// userInfo keys:
    /// - "itemID" (UUID)
    /// - "boardName" (String)
    /// - "isColdStart" (Bool)
    /// - "mode" (String: existing/create)
    /// - "boardID" (String UUID, optional)
    /// - "confidence" (Double)
    /// - "reason" (String, optional)
    /// - "alternatives" (comma-separated UUID list, optional)
    static let groveNewBoardSuggestion = Notification.Name("groveNewBoardSuggestion")
}

/// Response shape expected from the LLM for auto-tagging.
private struct AutoTagResponse: Decodable {
    struct TagEntry: Decodable {
        let name: String
        let category: String?
        let confidence: Double?
    }

    let tags: [TagEntry]
    let one_line_summary: String?
    let suggested_board: String?
}

/// Protocol for auto-tagging items via LLM.
protocol AutoTagServiceProtocol {
    @MainActor func tagItem(_ itemID: Item.ID) async
}

/// Generates tags, a one-line summary, and a suggested board for an Item using the LLM.
/// Gracefully degrades — if the LLM is unavailable or returns bad data,
/// the item is left unchanged.
@MainActor
final class AutoTagService: AutoTagServiceProtocol {
    private let database: any DatabaseWriter
    private let provider: LLMProvider
    private let entitlement: EntitlementService

    init(
        database: any DatabaseWriter = AppDatabase.current,
        provider: LLMProvider = LLMServiceConfig.makeProvider(),
        entitlement: EntitlementService = .shared
    ) {
        self.database = database
        self.provider = provider
        self.entitlement = entitlement
    }

    @MainActor func tagItem(_ itemID: Item.ID) async {
        guard LLMServiceConfig.isConfigured else { return }
        guard entitlement.canUse(.autoTagging) else { return }

        // Gather existing board names to help the LLM suggest one
        let snapshot = database.attemptRead { db in
            (item: try Item.find(itemID).fetchOne(db), boardNames: try Board.all.fetchAll(db).map(\.title))
        }
        guard let item = snapshot?.item else { return }
        let boardNames = snapshot?.boardNames ?? []
        let boardList = boardNames.isEmpty ? "none" : boardNames.joined(separator: ", ")

        let systemPrompt = """
        You are a knowledge-management assistant. Given an item's title, source URL, and content excerpt, \
        return a JSON object with:
        - "tags": an array of objects, each with "name" (lowercase, 1-3 words), \
          "category" (one of: topic, concept, technology, person, custom), and \
          "confidence" (0.0-1.0).
        - "one_line_summary": a single sentence summarizing the item (max 120 characters). \
          This field is REQUIRED — always return a summary even if content is minimal. \
          Use the title and URL to infer the topic if needed.
        - "suggested_board": the best board name for this item. Prefer an existing board if one fits. \
          If none fit, suggest a concise, reusable topic name (2-4 words) that could group related items. \
          Avoid one-off labels; think in terms of durable categories.
        Return 3-7 tags. Only return valid JSON, no extra text.
        """

        let contentExcerpt = String((item.content ?? "").prefix(1500))
        let userPrompt = """
        Title: \(item.title)
        Source URL: \(item.sourceURL ?? "none")
        Content:
        \(contentExcerpt)

        Existing boards: \(boardList)
        """

        guard let result = await provider.complete(system: systemPrompt, user: userPrompt, service: "tagging") else {
            return
        }

        guard let parsed = LLMJSONParser.decode(AutoTagResponse.self, from: result.content) else {
            return
        }

        // The LLM can take a while. Everything it returned goes in as one
        // transaction, which starts by checking the item is still there: tag
        // links have a foreign key, so a deleted item would fail the whole write.
        var suggestion: (decision: BoardSuggestionDecision, isColdStart: Bool)?
        let applied = database.attempt { db -> Bool in
            guard try Item.find(itemID).fetchOne(db) != nil else { return false }

            // Apply tags
            for entry in parsed.tags {
                let tagName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !tagName.isEmpty else { continue }

                let confidence = Float(min(max(entry.confidence ?? 0.5, 0), 1))
                let category = TagCategory(rawValue: entry.category ?? "custom") ?? .custom

                // Reuse existing tag with the same name if one exists
                let existing = try Tag.where { $0.name.eq(tagName) }.fetchOne(db)

                if let existing {
                    try Item.addTag(existing.id, toItem: itemID, in: db)
                } else {
                    let tag = Tag(name: tagName, category: category, isAutoGenerated: true, confidence: confidence)
                    try Tag.insert { tag }.execute(db)
                    try Item.addTag(tag.id, toItem: itemID, in: db)
                }
            }

            // Apply one-line summary
            if let summary = parsed.one_line_summary, !summary.isEmpty {
                try Item.modify(itemID, in: db) {
                    $0.metadata["summary"] = String(summary.prefix(120))
                }
            }

            // Apply suggested board
            if let suggestedBoard = parsed.suggested_board, !suggestedBoard.isEmpty {
                // Read after the tags above: the engine scores boards by them.
                let library = try Library.fetch(db)
                guard let taggedItem = library.item(itemID) else { return false }

                let suggestionEngine = BoardSuggestionEngine()
                let decision = suggestionEngine.resolveSuggestion(
                    for: taggedItem,
                    suggestedName: suggestedBoard,
                    boards: library.boards
                )
                try Item.modify(itemID, in: db) { BoardSuggestionMetadata.apply(decision, to: &$0) }
                suggestion = (decision, library.boards.isEmpty)
            }

            return true
        }
        guard applied == true else { return }

        entitlement.recordUse(.autoTagging)

        if let suggestion {
            NotificationCenter.default.post(
                name: .groveNewBoardSuggestion,
                object: nil,
                userInfo: BoardSuggestionMetadata.notificationUserInfo(
                    itemID: itemID,
                    decision: suggestion.decision,
                    isColdStart: suggestion.isColdStart
                )
            )
        }
    }
}
