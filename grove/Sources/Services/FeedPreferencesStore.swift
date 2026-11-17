import Foundation

/// UserDefaults-backed preferences for the newsletters-via-RSS pipeline:
/// directory cards the user dismissed.
enum FeedPreferencesStore {
    private static let dismissedCatalogKey = "grove.feeds.dismissedCatalogIDs"

    private static var defaults: UserDefaults { .standard }

    // MARK: - Directory Card Dismissals

    static func isCatalogEntryDismissed(_ id: String) -> Bool {
        Set(defaults.stringArray(forKey: dismissedCatalogKey) ?? []).contains(id)
    }

    static func dismissCatalogEntry(_ id: String) {
        var ids = Set(defaults.stringArray(forKey: dismissedCatalogKey) ?? [])
        ids.insert(id)
        defaults.set(Array(ids), forKey: dismissedCatalogKey)
    }
}
