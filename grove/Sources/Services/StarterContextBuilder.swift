import Foundation

// MARK: - Context Types

/// Aggregated context used by conversation starter generators.
struct StarterContext {
    let recentItems: [Item]          // last 7 days
    let staleItems: [Item]           // untouched 30+ days with reflections
    let contradictionItems: [Item]   // items with .contradicts outgoing connections
    let contradictionPairs: [ContradictionPair]  // actual contradicting item pairs, with reason
    let topRecentTag: String?
    let topRecentTagCount: Int
    let unboardedCluster: UnboardedCluster?  // cluster of unboarded items sharing tags
}

/// A specific pair of items connected by a `.contradicts` edge, carrying the
/// one-sentence tension reason recorded on the connection (e.g. by
/// TensionDetectionService). This is what makes a "resolve the tension" starter
/// concrete rather than generic.
struct ContradictionPair {
    let source: Item
    let target: Item
    let reason: String?
}

/// A cluster of unboarded items sharing a common tag.
struct UnboardedCluster {
    let sharedTag: String
    let items: [Item]
    let count: Int
}

// MARK: - StarterContextBuilder

/// Builds `StarterContext` from a collection of Items for conversation starter generation.
enum StarterContextBuilder {

    /// Builds aggregated context from the given items, identifying recent, stale,
    /// contradictory, tag-clustered, and unboarded items.
    @MainActor
    static func buildContext(from allItems: [Item]) -> StarterContext {
        let suggestionEligibleItems = allItems.filter { $0.isIncludedInDiscussionSuggestions }
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3600)

        let recentItems = suggestionEligibleItems.filter {
            ($0.status == .active || $0.status == .inbox)
                && !$0.isFeedSuggestion
                && $0.createdAt > sevenDaysAgo
        }

        let staleItems = suggestionEligibleItems.filter {
            $0.status == .active &&
            $0.updatedAt < thirtyDaysAgo &&
            !$0.reflections.isEmpty
        }

        let contradictionItems = suggestionEligibleItems.filter {
            $0.outgoingConnections.contains { $0.type == .contradicts }
        }

        let contradictionPairs = buildContradictionPairs(from: suggestionEligibleItems)

        // Top tag in recent items
        let recentTags = recentItems.flatMap { $0.tags.map(\.name) }
        let tagCounts = Dictionary(recentTags.map { ($0, 1) }, uniquingKeysWith: +)
        let topEntry = tagCounts.max(by: { $0.value < $1.value })

        // Unboarded cluster: items with no board assignment
        let unboardedCluster = findUnboardedCluster(from: suggestionEligibleItems)

        return StarterContext(
            recentItems: recentItems,
            staleItems: staleItems,
            contradictionItems: contradictionItems,
            contradictionPairs: contradictionPairs,
            topRecentTag: topEntry?.key,
            topRecentTagCount: topEntry?.value ?? 0,
            unboardedCluster: unboardedCluster
        )
    }

    /// Collects distinct `.contradicts` connections between two suggestion-eligible
    /// items, deduplicated by unordered pair. Pairs whose connection carries a
    /// reason note are ranked first, since they yield more concrete starters.
    @MainActor
    private static func buildContradictionPairs(from items: [Item]) -> [ContradictionPair] {
        let eligibleIDs = Set(items.map(\.id))
        var seen = Set<String>()
        var pairs: [ContradictionPair] = []

        for item in items {
            for connection in item.outgoingConnections where connection.type == .contradicts {
                guard let source = connection.sourceItem,
                      let target = connection.targetItem,
                      eligibleIDs.contains(source.id),
                      eligibleIDs.contains(target.id),
                      source.id != target.id else { continue }

                let key = [source.id.uuidString, target.id.uuidString].sorted().joined(separator: "|")
                guard seen.insert(key).inserted else { continue }

                let reason = connection.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                pairs.append(ContradictionPair(
                    source: source,
                    target: target,
                    reason: (reason?.isEmpty == false) ? reason : nil
                ))
            }
        }

        let withReason = pairs.filter { $0.reason != nil }
        let withoutReason = pairs.filter { $0.reason == nil }
        return withReason + withoutReason
    }

    /// Returns sorted, deduplicated board IDs for a set of items.
    @MainActor
    static func boardIDs(for items: [Item]) -> [UUID] {
        let ids = items.flatMap { $0.boards.map(\.id) }
        let unique = Set(ids)
        return unique.sorted { $0.uuidString < $1.uuidString }
    }

    // MARK: - Private

    /// Finds a cluster of unboarded items sharing 2+ tags, with at least 4 items total.
    /// Returns the largest such cluster, keyed on the most-shared tag.
    @MainActor
    private static func findUnboardedCluster(from allItems: [Item]) -> UnboardedCluster? {
        let unboarded = allItems.filter {
            $0.boards.isEmpty
                && ($0.status == .active || $0.status == .inbox)
                && !$0.isFeedSuggestion
        }
        guard unboarded.count >= 4 else { return nil }

        // Count how many unboarded items share each tag
        let tagGroups = Dictionary(grouping: unboarded.flatMap { item in
            item.tags.map { tag in (tag.name, item) }
        }, by: { $0.0 })

        // Find the tag with the most unboarded items (at least 4 items)
        let bestEntry = tagGroups
            .filter { $0.value.count >= 4 }
            .max(by: { $0.value.count < $1.value.count })

        guard let (tag, pairs) = bestEntry else { return nil }

        // Require that at least 2 distinct tags are shared across these items (quality check)
        let clusterItems = pairs.map(\.1)
        let sharedTagNames = Set(clusterItems.flatMap { $0.tags.map(\.name) })
        guard sharedTagNames.count >= 2 else { return nil }

        return UnboardedCluster(sharedTag: tag, items: clusterItems, count: clusterItems.count)
    }
}
