import Foundation
import SQLiteData

/// Callback type for board suggestion events, replacing the NotificationCenter notification.
typealias BoardSuggestionCallback = @MainActor @Sendable (UUID, BoardSuggestionDecision, Bool) -> Void

/// Wraps AutoTagService + BoardSuggestionEngine calls for auto-tagging items.
/// Extracted from CaptureService to isolate tagging responsibility.
@MainActor
@Observable
final class ItemAutoTagger {
    private let database: any DatabaseWriter

    /// Optional callback invoked when a board suggestion is generated.
    /// Parameters: (itemID, decision, isColdStart)
    var onBoardSuggestion: BoardSuggestionCallback?

    init(
        database: any DatabaseWriter = AppDatabase.current,
        onBoardSuggestion: BoardSuggestionCallback? = nil
    ) {
        self.database = database
        self.onBoardSuggestion = onBoardSuggestion
    }

    /// Runs auto-tagging on an item.
    /// If AI is configured, delegates to AutoTagService.
    /// Otherwise, performs cold-start heuristic board suggestions.
    func autoTagItem(itemID: UUID) async {
        if LLMServiceConfig.isConfigured {
            let service = AutoTagService(database: database)
            await service.tagItem(itemID)
        } else {
            await coldStartHeuristic(itemID: itemID)
        }
    }

    // MARK: - Cold Start Heuristic

    /// When no LLM is configured and no boards exist, suggest a board name
    /// derived from the item title for the first few captures.
    private func coldStartHeuristic(itemID: UUID) async {
        let snapshot = database.attemptRead { db in
            (item: try ItemGraph.fetch(itemID, in: db), boardCount: try Board.all.fetchCount(db))
        }
        guard let item = snapshot?.item, snapshot?.boardCount == 0 else { return }

        let captureCount = UserDefaults.standard.integer(forKey: "grove.coldStartCaptureCount")
        guard captureCount < 3 else { return }
        UserDefaults.standard.set(captureCount + 1, forKey: "grove.coldStartCaptureCount")

        let words = item.title
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .prefix(3)
        let suggestedName = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        guard !suggestedName.isEmpty else { return }

        let suggestionEngine = BoardSuggestionEngine()
        let decision = suggestionEngine.resolveSuggestion(
            for: item,
            suggestedName: suggestedName,
            boards: []
        )
        database.attempt { db in
            try Item.modify(itemID, in: db) { BoardSuggestionMetadata.apply(decision, to: &$0) }
        }

        // Use callback if provided, otherwise fall back to notification
        if let callback = onBoardSuggestion {
            callback(item.id, decision, true)
        } else {
            NotificationCenter.default.post(
                name: .groveNewBoardSuggestion,
                object: nil,
                userInfo: BoardSuggestionMetadata.notificationUserInfo(
                    itemID: item.id,
                    decision: decision,
                    isColdStart: true
                )
            )
        }
    }
}
