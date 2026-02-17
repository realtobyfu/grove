import Foundation
import SwiftData

/// Manages spaced resurfacing of items based on engagement patterns.
/// Items enter the queue when they have annotations or connections.
/// Interval adapts: doubles after engagement, resets after 60 days of inactivity.
@MainActor
@Observable
final class ResurfacingService {
    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Interval Algorithm

    /// Update resurfacing interval for an item after engagement.
    /// Each engagement doubles the interval (user already knows the material).
    func recordEngagement(for item: Item) {
        item.lastEngagedAt = .now
        item.resurfaceCount += 1

        // Double the interval on each engagement, capped at 120 days
        let newInterval = min(item.resurfaceIntervalDays * 2, 120)
        item.resurfaceIntervalDays = newInterval

        try? modelContext.save()
    }

    /// Check all items and reset intervals for those with 60+ days of no engagement.
    func resetStaleIntervals() {
        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: .now) ?? .now

        for item in allItems where item.isResurfacingEligible && item.status == .active {
            let lastActivity = item.lastEngagedAt ?? item.lastResurfacedAt ?? item.createdAt
            if lastActivity < sixtyDaysAgo && item.resurfaceIntervalDays > 7 {
                item.resurfaceIntervalDays = 7
            }
        }

        try? modelContext.save()
    }

    /// Mark an item as resurfaced (nudge was shown).
    func markResurfaced(_ item: Item) {
        item.lastResurfacedAt = .now
        try? modelContext.save()
    }

    // MARK: - Queue Queries

    /// Get the next item eligible for resurfacing.
    /// Returns the most overdue item first.
    func nextResurfaceCandidate(excludingItemIDs: Set<UUID> = []) -> Item? {
        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []

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

    /// Get context for a resurface nudge: a key annotation or connection title.
    func resurfaceContext(for item: Item) -> String? {
        // Prefer the most recent annotation as context
        if let latestAnnotation = item.annotations.sorted(by: { $0.createdAt > $1.createdAt }).first {
            let preview = String(latestAnnotation.content.prefix(80))
            let suffix = latestAnnotation.content.count > 80 ? "..." : ""
            return "Your note: \"\(preview)\(suffix)\""
        }

        // Fall back to a connected item title
        if let connection = item.outgoingConnections.first, let target = connection.targetItem {
            return "Connected to: \(target.title)"
        }
        if let connection = item.incomingConnections.first, let source = connection.sourceItem {
            return "Connected to: \(source.title)"
        }

        return nil
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
        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []

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
