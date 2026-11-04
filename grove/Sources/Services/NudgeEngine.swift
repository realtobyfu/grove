import Foundation
import SQLiteData

/// Protocol for nudge engine.
@MainActor
protocol NudgeEngineProtocol {
    func startSchedule()
    func stopSchedule()
    func generateNudges()
}

/// Generates nudges based on item status, engagement patterns, and user settings.
/// Supports two nudge types: resurface (spaced resurfacing) and staleInbox.
/// Proactive conversation starters are handled by ConversationStarterService on the home screen.
/// Runs on a configurable schedule (default every 4 hours) and respects daily limits.
@MainActor
@Observable
final class NudgeEngine: NudgeEngineProtocol {
    private let database: any DatabaseWriter
    private var nudgeTask: Task<Void, Never>?
    private var readLaterTask: Task<Void, Never>?
    private(set) var resurfacingService: ResurfacingService
    private(set) var readLaterService: ReadLaterService

    init(database: any DatabaseWriter = AppDatabase.current) {
        self.database = database
        self.resurfacingService = ResurfacingService(database: database)
        self.readLaterService = ReadLaterService(database: database)
    }

    // MARK: - Scheduling

    /// Start periodic nudge generation. Call once on app launch.
    func startSchedule() {
        processReadLaterQueue()
        generateNudges()
        let intervalNanos = UInt64(NudgeSettings.scheduleIntervalHours) * 3_600_000_000_000
        nudgeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanos)
                guard !Task.isCancelled else { break }
                self?.generateNudges()
            }
        }

        // Read-later queue checks run independently so deferred inbox items return on time.
        readLaterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                self?.processReadLaterQueue()
            }
        }
    }

    func stopSchedule() {
        nudgeTask?.cancel()
        nudgeTask = nil
        readLaterTask?.cancel()
        readLaterTask = nil
    }

    /// Generate active nudge types: spaced resurfacing and stale inbox.
    /// Streak, continue-course, connection-prompt, smart, and check-in nudges are removed —
    /// their role is now served by ConversationStarterService prompt bubbles on the home screen.
    func generateNudges() {
        // Before anything reads the nudge table: retire the ones that can no
        // longer reach anybody. Every generation path comes through here, and
        // the dedupe guards below count these ghosts, so the sweep has to
        // happen first or a single invisible nudge blocks its whole category
        // forever.
        sweepUnreachableNudges()

        processReadLaterQueue()

        // Reset stale resurfacing intervals (60+ days no engagement → back to 7 days)
        resurfacingService.resetStaleIntervals()

        let todayNudgeCount = nudgesCreatedToday()
        let maxPerDay = NudgeSettings.maxNudgesPerDay

        // Don't create more than maxPerDay unless user has high engagement
        guard todayNudgeCount < maxPerDay || userHasHighEngagement() else { return }

        if NudgeSettings.resurfaceEnabled && EntitlementService.shared.isPro {
            generateSpacedResurfaceNudge()
        }
        if NudgeSettings.staleInboxEnabled {
            generateStaleInboxNudge()
        }
    }

    private func processReadLaterQueue() {
        _ = readLaterService.restoreDueItems()
    }

    // MARK: - Unreachable Nudge Sweep

    /// Marks pending/shown nudges that have no surface left as dismissed.
    ///
    /// Two kinds go permanently invisible while still counting against the
    /// "don't create a second one" guards, which deadlocks their generator:
    ///
    /// - a `staleInbox` nudge while system notifications are off — the Today
    ///   list on Home only renders `resurface` nudges, so a notification is
    ///   its only surface and there isn't one;
    /// - a `resurface` nudge with no `targetItemID` — Home filters it out
    ///   (nothing to open), but the pending check still sees it. Deleting an
    ///   item takes its nudges with it, so these are rows that were imported
    ///   already orphaned.
    ///
    /// Idempotent: a swept nudge is `.dismissed` and never matches again.
    func sweepUnreachableNudges() {
        let notificationsEnabled = NudgeSettings.notificationsEnabled

        database.attempt { db in
            for nudge in try Nudge.all.fetchAll(db) where nudge.status == .pending || nudge.status == .shown {
                let isUnreachable: Bool
                switch nudge.type {
                case .staleInbox:
                    isUnreachable = !notificationsEnabled
                case .resurface:
                    isUnreachable = nudge.targetItemID == nil
                default:
                    isUnreachable = false
                }
                guard isUnreachable else { continue }
                try Nudge.modify(nudge.id, in: db) { $0.status = .dismissed }
            }
        }
    }

    // MARK: - Reads

    private func fetchNudges() -> [Nudge] {
        database.attemptRead { try Nudge.all.fetchAll($0) } ?? []
    }

    private func fetchItems() -> [ItemGraph] {
        database.attemptRead { try Library.fetch($0).items } ?? []
    }

    // MARK: - Daily Limit Helpers

    private func nudgesCreatedToday() -> Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return fetchNudges().filter { $0.createdAt >= startOfDay }.count
    }

    /// High engagement = user has acted on 3+ nudges in the past 7 days.
    private func userHasHighEngagement() -> Bool {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -AppConstants.Days.recent, to: .now) ?? .now
        let recentActedOn = fetchNudges().filter { $0.status == .actedOn && $0.createdAt > sevenDaysAgo }
        return recentActedOn.count >= AppConstants.Nudge.highEngagementThreshold
    }

    /// Check if adding another nudge would exceed the daily limit.
    private func canCreateNudge() -> Bool {
        let todayCount = nudgesCreatedToday()
        let maxPerDay = NudgeSettings.maxNudgesPerDay
        return todayCount < maxPerDay || userHasHighEngagement()
    }

    // MARK: - Spaced Resurface Nudge

    /// Uses adaptive interval resurfacing: items with annotations/connections enter
    /// a queue. Interval doubles after each engagement, resets after 60 days of inactivity.
    private func generateSpacedResurfaceNudge() {
        guard canCreateNudge() else { return }
        guard !NudgeSettings.spacedResurfacingGlobalPause else { return }

        let allNudges = fetchNudges()

        // Don't create if there's already a pending/shown resurface nudge
        let hasPending = allNudges.contains {
            $0.type == .resurface && ($0.status == .pending || $0.status == .shown)
        }
        guard !hasPending else { return }

        // Get IDs of items with recently dismissed resurface nudges
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -AppConstants.Days.recent, to: .now) ?? .now
        let recentlyDismissedIDs = Set(
            allNudges
                .filter { $0.type == .resurface && $0.status == .dismissed && $0.createdAt > sevenDaysAgo }
                .compactMap(\.targetItemID)
        )

        // Use ResurfacingService to find the best candidate
        guard let chosen = resurfacingService.nextResurfaceCandidate(excludingItemIDs: recentlyDismissedIDs) else {
            // Fall back to old behavior for items without annotations/connections
            generateLegacyResurfaceNudge(excludingIDs: recentlyDismissedIDs, allNudges: allNudges)
            return
        }

        // Check per-board nudge frequency
        guard !isBoardNudgeDisabled(for: chosen) else { return }

        // Build message with context
        var message = "You saved \"\(chosen.title)\" — time to revisit?"
        if let context = resurfacingService.resurfaceContext(for: chosen) {
            message += " \(context)"
        }

        let nudge = Nudge(type: .resurface, message: message, targetItemID: chosen.id)
        resurfacingService.markResurfaced(chosen.id)
        database.attempt { db in try Nudge.insert { nudge }.execute(db) }
        NudgeNotificationService.shared.schedule(for: nudge)
    }

    /// Fallback for items without annotations/connections — uses the original
    /// 14-day stale threshold to still surface forgotten items.
    private func generateLegacyResurfaceNudge(excludingIDs: Set<UUID>, allNudges: [Nudge]) {
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -AppConstants.Days.stale, to: .now) ?? .now
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -AppConstants.Days.cooldown, to: .now) ?? .now

        let staleActiveItems = fetchItems().filter {
            $0.status == .active && $0.updatedAt < fourteenDaysAgo &&
            !$0.isResurfacingEligible // Only items not in the spaced queue
        }
        guard !staleActiveItems.isEmpty else { return }

        let dismissedItemIDs = Set(
            allNudges
                .filter { $0.type == .resurface && $0.status == .dismissed && $0.createdAt > thirtyDaysAgo }
                .compactMap(\.targetItemID)
        )

        let candidates = staleActiveItems.filter { item in
            !dismissedItemIDs.contains(item.id) && !excludingIDs.contains(item.id) &&
            !isBoardNudgeDisabled(for: item)
        }
        guard let chosen = candidates.randomElement() else { return }

        let daysSaved = Calendar.current.dateComponents([.day], from: chosen.createdAt, to: .now).day ?? 0
        let message = "You saved \"\(chosen.title)\" \(daysSaved) days ago. Still relevant?"

        let nudge = Nudge(type: .resurface, message: message, targetItemID: chosen.id)
        database.attempt { db in try Nudge.insert { nudge }.execute(db) }
        NudgeNotificationService.shared.schedule(for: nudge)
    }

    // MARK: - Stale Inbox Nudge

    /// If inbox has 5+ items older than 14 days, creates a stale inbox nudge.
    private func generateStaleInboxNudge() {
        guard canCreateNudge() else { return }

        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -AppConstants.Days.stale, to: .now) ?? .now
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -AppConstants.Days.cooldown, to: .now) ?? .now

        let staleInboxItems = fetchItems().filter {
            $0.status == .inbox && !$0.isFeedSuggestion && $0.createdAt < fourteenDaysAgo
        }
        guard staleInboxItems.count >= AppConstants.Nudge.staleInboxMinCount else { return }

        let allNudges = fetchNudges()

        let hasPending = allNudges.contains {
            $0.type == .staleInbox && ($0.status == .pending || $0.status == .shown)
        }
        guard !hasPending else { return }

        let recentlyDismissed = allNudges.contains {
            $0.type == .staleInbox && $0.status == .dismissed && $0.createdAt > thirtyDaysAgo
        }
        guard !recentlyDismissed else { return }

        let message = "You have \(staleInboxItems.count) items waiting in your inbox"

        let nudge = Nudge(type: .staleInbox, message: message)
        database.attempt { db in try Nudge.insert { nudge }.execute(db) }
        NudgeNotificationService.shared.schedule(for: nudge)
    }

    // MARK: - Per-Board Frequency

    /// Check if the item's board has nudges disabled.
    private func isBoardNudgeDisabled(for item: ItemGraph) -> Bool {
        // If item has no board, nudges are allowed
        guard let board = item.board else { return false }
        return board.nudgeFrequencyHours == -1
    }
}
