import Foundation
import SQLiteData
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
enum LearningWidgetSnapshotStore {
    static func refresh(database: any DatabaseWriter = AppDatabase.current) {
        // Do not create preferences as a side effect of a widget update.
        let preferences = database.attemptRead { db in
            try LearningPreferences.find(LearningPreferences.sharedID).fetchOne(db)
        } ?? nil
        let cards = database.attemptRead { db in try Flashcard.all.fetchAll(db) } ?? []
        let focus = preferences?.focusBoardIDs ?? []
        let snapshot = LearningWidgetSnapshot(
            sessionMinutes: min(5, max(1, preferences?.sessionMinutes ?? 3)),
            hasCards: cards.contains { card in
                !card.isSuspended && card.deletedAt == nil
                    && (focus.isEmpty || card.boardIDs.contains(where: focus.contains))
            },
            boardID: focus.count == 1 ? focus.first : nil,
            updatedAt: .now
        )
        guard snapshot.hasCards != LearningWidgetSnapshotStorage.read().hasCards
                || snapshot.boardID != LearningWidgetSnapshotStorage.read().boardID
                || snapshot.sessionMinutes != LearningWidgetSnapshotStorage.read().sessionMinutes
        else { return }
        LearningWidgetSnapshotStorage.write(snapshot)
        #if canImport(WidgetKit) && !SHARE_EXTENSION
        WidgetCenter.shared.reloadTimelines(ofKind: "GroveLearningWidget")
        #endif
    }
}
