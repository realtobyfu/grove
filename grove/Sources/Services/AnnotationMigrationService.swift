import Foundation
import SQLiteData

@MainActor
final class AnnotationMigrationService {
    private static let migratedKey = "grove.annotationsMigrated"

    static var hasMigrated: Bool {
        UserDefaults.standard.bool(forKey: migratedKey)
    }

    static func migrateIfNeeded(database: any DatabaseWriter = AppDatabase.current) {
        guard !hasMigrated else { return }

        let migrated: Void? = database.attempt { db in
            for annotation in try Annotation.all.fetchAll(db) {
                guard let itemID = annotation.itemID else { continue }

                // Read each time: the blocks inserted for this item's earlier
                // annotations have to count, or they'd share a position.
                let positions = try ReflectionBlock
                    .where { $0.itemID.eq(itemID) }
                    .select(\.position)
                    .fetchAll(db)
                var block = ReflectionBlock(
                    itemID: itemID,
                    blockType: .keyInsight,
                    content: annotation.content,
                    highlight: annotation.highlight,
                    position: (positions.max() ?? -1) + 1,
                    videoTimestamp: annotation.position
                )
                block.createdAt = annotation.createdAt
                let row = block
                try ReflectionBlock.insert { row }.execute(db)
            }
        }

        // A failed pass rolled back whole, so it's safe to run again next launch.
        guard migrated != nil else { return }
        UserDefaults.standard.set(true, forKey: migratedKey)
    }
}
