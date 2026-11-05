import Foundation
import SwiftData

/// Protocol for nudge engine.
@MainActor
protocol NudgeEngineProtocol {
    func startSchedule()
    func stopSchedule()
    func generateNudges()
}

/// Generates stale-inbox nudges and returns Read Later items when they come due.
/// Proactive conversation starters are handled by ConversationStarterService on the home screen.
/// Runs every few hours and respects a daily limit.
@MainActor
@Observable
final class NudgeEngine: NudgeEngineProtocol {
    private var modelContext: ModelContext
    private var nudgeTask: Task<Void, Never>?
    private var readLaterTask: Task<Void, Never>?
    private(set) var readLaterService: ReadLaterService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.readLaterService = ReadLaterService(modelContext: modelContext)
    }

    // MARK: - Scheduling

    /// Start periodic nudge generation. Call once on app launch.
    func startSchedule() {
        processReadLaterQueue()
        generateNudges()
        let intervalNanos = UInt64(AppConstants.Nudge.scheduleIntervalHours) * 3_600_000_000_000
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

    /// Generate the one active nudge type: stale inbox.
    /// Spaced resurfacing, streak, continue-course, connection-prompt, smart, and
    /// check-in nudges are retired; conversation starters on the home screen
    /// cover the "think about this again" role.
    func generateNudges() {
        // Before anything reads the nudge table: retire the ones that can no
        // longer reach anybody. Every generation path comes through here, and
        // the dedupe guards below count these ghosts, so the sweep has to
        // happen first or a single invisible nudge blocks its whole category
        // forever.
        sweepUnreachableNudges()

        processReadLaterQueue()

        // Don't create more than the daily cap unless user has high engagement
        guard canCreateNudge() else { return }

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
    /// "don't create a second one" guards:
    ///
    /// - a `staleInbox` nudge while system notifications are off — a
    ///   notification is its real surface; Today shows the live inbox instead;
    /// - any `resurface` nudge — spaced resurfacing is retired and nothing
    ///   renders these any more, so ones already in a store are retired here
    ///   and their delivered notifications withdrawn.
    ///
    /// Idempotent: a swept nudge is `.dismissed` and never matches again.
    func sweepUnreachableNudges() {
        let notificationsEnabled = NudgeSettings.notificationsEnabled
        let allNudges: [Nudge] = modelContext.fetchAll()
        var sweptIDs: [UUID] = []

        for nudge in allNudges where nudge.status == .pending || nudge.status == .shown {
            let isUnreachable: Bool
            switch nudge.type {
            case .staleInbox:
                isUnreachable = !notificationsEnabled
            case .resurface:
                isUnreachable = true
            default:
                isUnreachable = false
            }
            guard isUnreachable else { continue }
            nudge.status = .dismissed
            sweptIDs.append(nudge.id)
        }

        guard !sweptIDs.isEmpty else { return }
        try? modelContext.save()
        for id in sweptIDs {
            NudgeNotificationService.shared.cancel(for: id)
        }
    }

    // MARK: - Daily Limit Helpers

    private func nudgesCreatedToday() -> Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let allNudges: [Nudge] = modelContext.fetchAll()
        return allNudges.filter { $0.createdAt >= startOfDay }.count
    }

    /// High engagement = user has acted on 3+ nudges in the past 7 days.
    private func userHasHighEngagement() -> Bool {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -AppConstants.Days.recent, to: .now) ?? .now
        let allNudges: [Nudge] = modelContext.fetchAll()
        let recentActedOn = allNudges.filter { $0.status == .actedOn && $0.createdAt > sevenDaysAgo }
        return recentActedOn.count >= AppConstants.Nudge.highEngagementThreshold
    }

    /// Check if adding another nudge would exceed the daily limit.
    private func canCreateNudge() -> Bool {
        nudgesCreatedToday() < AppConstants.Nudge.maxPerDay || userHasHighEngagement()
    }

    // MARK: - Stale Inbox Nudge

    /// If inbox has 5+ items older than 14 days, creates a stale inbox nudge.
    private func generateStaleInboxNudge() {
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -AppConstants.Days.stale, to: .now) ?? .now
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -AppConstants.Days.cooldown, to: .now) ?? .now

        let allItems: [Item] = modelContext.fetchAll()
        let staleInboxItems = allItems.filter {
            $0.status == .inbox && !$0.isFeedSuggestion && $0.createdAt < fourteenDaysAgo
        }
        guard staleInboxItems.count >= AppConstants.Nudge.staleInboxMinCount else { return }

        let allNudges: [Nudge] = modelContext.fetchAll()

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
        modelContext.insert(nudge)
        try? modelContext.save()
        NudgeNotificationService.shared.schedule(for: nudge)
    }
}
