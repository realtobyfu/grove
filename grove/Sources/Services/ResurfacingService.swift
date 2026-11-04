import Foundation
import SQLiteData

/// Protocol for resurfacing service.
@MainActor
protocol ResurfacingServiceProtocol {
    func recordEngagement(for itemID: Item.ID)
    func nextResurfaceCandidate(excludingItemIDs: Set<UUID>) -> ItemGraph?
}

/// Manages spaced resurfacing of items based on engagement patterns.
/// Items enter the queue when they have annotations or connections.
/// Interval adapts: doubles after engagement, resets after 60 days of inactivity.
@MainActor
@Observable
final class ResurfacingService: ResurfacingServiceProtocol {
    private let database: any DatabaseWriter

    init(database: any DatabaseWriter = AppDatabase.current) {
        self.database = database
    }

    // MARK: - Interval Algorithm

    /// Update resurfacing interval for an item after engagement.
    /// Each engagement doubles the interval (user already knows the material).
    func recordEngagement(for itemID: Item.ID) {
        database.attempt { db in
            try Item.modify(itemID, in: db) { item in
                item.lastEngagedAt = .now
                item.resurfaceCount += 1

                // Double the interval on each engagement, capped at 120 days
                let newInterval = min(item.resurfaceIntervalDays * 2, 120)
                item.resurfaceIntervalDays = newInterval
            }
        }
    }

    /// Check all items and reset intervals for those with 60+ days of no engagement.
    func resetStaleIntervals() {
        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -AppConstants.Days.deepInactivity, to: .now) ?? .now

        database.attempt { db in
            for item in try Library.fetch(db).items where item.isResurfacingEligible && item.status == .active {
                let lastActivity = item.lastEngagedAt ?? item.lastResurfacedAt ?? item.createdAt
                if lastActivity < sixtyDaysAgo && item.resurfaceIntervalDays > 7 {
                    try Item.modify(item.id, in: db) { $0.resurfaceIntervalDays = 7 }
                }
            }
        }
    }

    /// Mark an item as resurfaced (nudge was shown).
    func markResurfaced(_ itemID: Item.ID) {
        database.attempt { db in
            try Item.modify(itemID, in: db) { $0.lastResurfacedAt = .now }
        }
    }

    // MARK: - Queue Queries

    /// Get the next item eligible for resurfacing.
    /// Returns the most overdue item first.
    func nextResurfaceCandidate(excludingItemIDs: Set<UUID> = []) -> ItemGraph? {
        let allItems = database.attemptRead { try Library.fetch($0).items } ?? []

        return allItems
            .filter { item in
                item.isResurfacingEligible &&
                item.status == .active &&
                !item.isResurfacingPaused &&
                !excludingItemIDs.contains(item.id) &&
                (item.nextResurfaceDate ?? .distantFuture) <= .now
            }
            .sorted { a, b in
                // Most overdue first
                (a.nextResurfaceDate ?? .distantPast) < (b.nextResurfaceDate ?? .distantPast)
            }
            .first
    }

    /// Get context for a resurface nudge: the user's own latest reflection.
    /// Connection titles are deliberately not used — they can be raw URLs or
    /// markdown and read as noise in a one-line nudge.
    func resurfaceContext(for item: ItemGraph) -> String? {
        guard let latestReflection = item.reflections.sorted(by: { $0.createdAt > $1.createdAt }).first else {
            return nil
        }
        let preview = String(latestReflection.content.prefix(AppConstants.LLM.reasonMaxLength))
        let suffix = latestReflection.content.count > AppConstants.LLM.reasonMaxLength ? "..." : ""
        return "Your note: \"\(preview)\(suffix)\""
    }

    // MARK: - Queue Statistics

    struct QueueStats {
        let totalInQueue: Int
        let upcoming: Int
        let overdue: Int
        let paused: Int
    }

    /// Compute queue statistics for the settings dashboard.
    func queueStats() -> QueueStats {
        let allItems = database.attemptRead { try Library.fetch($0).items } ?? []

        let eligible = allItems.filter { $0.isResurfacingEligible && $0.status == .active }
        let paused = eligible.filter { $0.isResurfacingPaused }.count
        let active = eligible.filter { !$0.isResurfacingPaused }

        let overdue = active.filter { $0.isResurfacingOverdue }.count
        let upcoming = active.count - overdue

        return QueueStats(
            totalInQueue: active.count,
            upcoming: upcoming,
            overdue: overdue,
            paused: paused
        )
    }
}
