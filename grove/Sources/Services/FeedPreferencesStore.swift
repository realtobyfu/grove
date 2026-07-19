import Foundation

/// UserDefaults-backed preferences for the newsletters-via-RSS pipeline:
/// dismissed discovered-feed suggestions, dismissed directory cards, and
/// per-source keep/dismiss counters used to throttle noisy feeds.
enum FeedPreferencesStore {
    private static let dismissedDiscoveredKey = "grove.feeds.dismissedDiscoveredURLs"
    private static let dismissedCatalogKey = "grove.feeds.dismissedCatalogIDs"
    private static let keepCountsKey = "grove.feeds.sourceKeepCounts"
    private static let dismissalCountsKey = "grove.feeds.sourceDismissalCounts"

    /// A source with at least this many dismissals and zero keeps is capped
    /// to one new suggestion per fetch cycle.
    static let throttleDismissalThreshold = 10

    private static var defaults: UserDefaults { .standard }

    // MARK: - Discovered Feed Suggestions

    /// Feed URLs the user dismissed from "Suggested from your library".
    /// Discovery skips these so they never reappear.
    static func isDiscoveryDismissed(_ feedURL: String) -> Bool {
        dismissedDiscoveredURLs().contains(feedURL)
    }

    static func dismissDiscovery(_ feedURL: String) {
        var urls = dismissedDiscoveredURLs()
        urls.insert(feedURL)
        defaults.set(Array(urls), forKey: dismissedDiscoveredKey)
    }

    private static func dismissedDiscoveredURLs() -> Set<String> {
        Set(defaults.stringArray(forKey: dismissedDiscoveredKey) ?? [])
    }

    // MARK: - Directory Card Dismissals

    static func isCatalogEntryDismissed(_ id: String) -> Bool {
        Set(defaults.stringArray(forKey: dismissedCatalogKey) ?? []).contains(id)
    }

    static func dismissCatalogEntry(_ id: String) {
        var ids = Set(defaults.stringArray(forKey: dismissedCatalogKey) ?? [])
        ids.insert(id)
        defaults.set(Array(ids), forKey: dismissedCatalogKey)
    }

    // MARK: - Per-Source Triage Signals

    static func recordKeep(sourceID: UUID) {
        increment(key: keepCountsKey, sourceID: sourceID)
    }

    static func recordDismissal(sourceID: UUID) {
        increment(key: dismissalCountsKey, sourceID: sourceID)
    }

    static func keepCount(sourceID: UUID) -> Int {
        counts(forKey: keepCountsKey)[sourceID.uuidString] ?? 0
    }

    static func dismissalCount(sourceID: UUID) -> Int {
        counts(forKey: dismissalCountsKey)[sourceID.uuidString] ?? 0
    }

    /// True when the user has consistently dismissed a source's suggestions
    /// without ever keeping one.
    static func isThrottled(sourceID: UUID) -> Bool {
        keepCount(sourceID: sourceID) == 0
            && dismissalCount(sourceID: sourceID) >= throttleDismissalThreshold
    }

    // MARK: - Helpers

    private static func counts(forKey key: String) -> [String: Int] {
        defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    private static func increment(key: String, sourceID: UUID) {
        var all = counts(forKey: key)
        all[sourceID.uuidString, default: 0] += 1
        defaults.set(all, forKey: key)
    }
}
