import Foundation
import SwiftData

/// Moves items overviewed by older builds to the current shape. See
/// `Item.migrateLegacyOverviewIfNeeded`.
@MainActor
enum OverviewMigrationService {
    /// Runs every launch rather than once: an old-shape item can still sync in
    /// from a device on an older build.
    static func migrateItems(context: ModelContext) {
        let items: [Item] = context.fetchAll()
        var didChange = false
        for item in items where item.migrateLegacyOverviewIfNeeded() {
            didChange = true
        }
        if didChange {
            try? context.save()
        }
    }
}
