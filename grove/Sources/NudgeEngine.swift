import Foundation
import SwiftData

/// Generates nudges based on item status, engagement patterns, and user settings.
/// Supports four nudge types: resurface, staleInbox, connectionPrompt, and streak.
/// Runs on a configurable schedule (default every 4 hours) and respects daily limits.
@MainActor
@Observable
final class NudgeEngine {
    private var modelContext: ModelContext
    private var timer: Timer?
    private(set) var resurfacingService: ResurfacingService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.resurfacingService = ResurfacingService(modelContext: modelContext)
    }

    // MARK: - Scheduling

    /// Start periodic nudge generation. Call once on app launch.
    func startSchedule() {
        generateNudges()
        let intervalSeconds = TimeInterval(NudgeSettings.scheduleIntervalHours) * 3600
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.generateNudges()
            }
        }
    }

    func stopSchedule() {
        timer?.invalidate()
        timer = nil
    }

    /// Generate all nudge types, respecting settings toggles and daily limits.
    func generateNudges() {
        // Reset stale resurfacing intervals (60+ days no engagement → back to 7 days)
        resurfacingService.resetStaleIntervals()

        let todayNudgeCount = nudgesCreatedToday()
        let maxPerDay = NudgeSettings.maxNudgesPerDay

        // Don't create more than maxPerDay unless user has high engagement
        guard todayNudgeCount < maxPerDay || userHasHighEngagement() else { return }

        if NudgeSettings.resurfaceEnabled {
            generateSpacedResurfaceNudge()
        }
        if NudgeSettings.staleInboxEnabled {
            generateStaleInboxNudge()
        }
        if NudgeSettings.connectionPromptEnabled {
            generateConnectionPromptNudge()
        }
        if NudgeSettings.streakEnabled {
            generateStreakNudge()
        }
        if NudgeSettings.continueCourseEnabled {
            generateContinueCourseNudge()
        }
    }

    // MARK: - Daily Limit Helpers

    private func nudgesCreatedToday() -> Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let allNudges = (try? modelContext.fetch(FetchDescriptor<Nudge>())) ?? []
        return allNudges.filter { $0.createdAt >= startOfDay }.count
    }

    /// High engagement = user has acted on 3+ nudges in the past 7 days.
    private func userHasHighEngagement() -> Bool {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let allNudges = (try? modelContext.fetch(FetchDescriptor<Nudge>())) ?? []
        let recentActedOn = allNudges.filter { $0.status == .actedOn && $0.createdAt > sevenDaysAgo }
        return recentActedOn.count >= 3
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

        let allNudges = (try? modelContext.fetch(FetchDescriptor<Nudge>())) ?? []

        // Don't create if there's already a pending/shown resurface nudge
        let hasPending = allNudges.contains {
            $0.type == .resurface && ($0.status == .pending || $0.status == .shown)
        }
        guard !hasPending else { return }

        // Get IDs of items with recently dismissed resurface nudges (within 7 days)
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let recentlyDismissedIDs = Set(
            allNudges
                .filter { $0.type == .resurface && $0.status == .dismissed && $0.createdAt > sevenDaysAgo }
                .compactMap { $0.targetItem?.id }
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

        let nudge = Nudge(type: .resurface, message: message, targetItem: chosen)
        resurfacingService.markResurfaced(chosen)
        modelContext.insert(nudge)
        try? modelContext.save()
    }

    /// Fallback for items without annotations/connections — uses the original
    /// 14-day stale threshold to still surface forgotten items.
    private func generateLegacyResurfaceNudge(excludingIDs: Set<UUID>, allNudges: [Nudge]) {
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now

        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        let staleActiveItems = allItems.filter {
            $0.status == .active && $0.updatedAt < fourteenDaysAgo &&
            !$0.isResurfacingEligible // Only items not in the spaced queue
        }
        guard !staleActiveItems.isEmpty else { return }

        let dismissedItemIDs = Set(
            allNudges
                .filter { $0.type == .resurface && $0.status == .dismissed && $0.createdAt > thirtyDaysAgo }
                .compactMap { $0.targetItem?.id }
        )

        let candidates = staleActiveItems.filter { item in
            !dismissedItemIDs.contains(item.id) && !excludingIDs.contains(item.id) &&
            !isBoardNudgeDisabled(for: item)
        }
        guard let chosen = candidates.randomElement() else { return }

        let daysSaved = Calendar.current.dateComponents([.day], from: chosen.createdAt, to: .now).day ?? 0
        let message = "You saved \"\(chosen.title)\" \(daysSaved) days ago. Still relevant?"

        let nudge = Nudge(type: .resurface, message: message, targetItem: chosen)
        modelContext.insert(nudge)
        try? modelContext.save()
    }

    // MARK: - Stale Inbox Nudge

    /// If inbox has 5+ items older than 14 days, creates a stale inbox nudge.
    private func generateStaleInboxNudge() {
        guard canCreateNudge() else { return }

        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now

        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        let staleInboxItems = allItems.filter {
            $0.status == .inbox && $0.createdAt < fourteenDaysAgo
        }
        guard staleInboxItems.count >= 5 else { return }

        let allNudges = (try? modelContext.fetch(FetchDescriptor<Nudge>())) ?? []

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
    }

    // MARK: - Connection Prompt Nudge

    /// Triggered when 3+ items share a tag within 7 days.
    /// "You added 3 articles on [topic] this week. Want to write a synthesis note?"
    private func generateConnectionPromptNudge() {
        guard canCreateNudge() else { return }

        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now

        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        let recentItems = allItems.filter { $0.createdAt > sevenDaysAgo && $0.status != .dismissed }

        // Group recent items by tag
        var tagItemMap: [UUID: (tag: Tag, items: [Item])] = [:]
        for item in recentItems {
            for tag in item.tags {
                if tagItemMap[tag.id] != nil {
                    tagItemMap[tag.id]?.items.append(item)
                } else {
                    tagItemMap[tag.id] = (tag: tag, items: [item])
                }
            }
        }

        // Find tags with 3+ items in the past week
        let hotTags = tagItemMap.values.filter { $0.items.count >= 3 }
            .sorted { $0.items.count > $1.items.count }

        guard let topCluster = hotTags.first else { return }

        let allNudges = (try? modelContext.fetch(FetchDescriptor<Nudge>())) ?? []

        // Check: don't create if pending/shown connectionPrompt already exists
        let hasPending = allNudges.contains {
            $0.type == .connectionPrompt && ($0.status == .pending || $0.status == .shown)
        }
        guard !hasPending else { return }

        // Check 30-day cooldown for this tag cluster
        let clusterItemIDs = Set(topCluster.items.map(\.id))
        let recentlyDismissed = allNudges.contains { nudge in
            nudge.type == .connectionPrompt &&
            nudge.status == .dismissed &&
            nudge.createdAt > thirtyDaysAgo &&
            nudge.relatedItemIDs != nil &&
            Set(nudge.relatedItemIDs ?? []).intersection(clusterItemIDs).count >= 2
        }
        guard !recentlyDismissed else { return }

        let tagName = topCluster.tag.name
        let count = topCluster.items.count
        let message = "You added \(count) articles on \(tagName) this week. Want to write a synthesis note?"

        let nudge = Nudge(type: .connectionPrompt, message: message)
        nudge.relatedItemIDs = Array(clusterItemIDs)
        modelContext.insert(nudge)
        try? modelContext.save()
    }

    // MARK: - Streak Nudge

    /// Triggered by consecutive days with opens/annotations in a board.
    /// "You've engaged with [board] 5 days in a row"
    private func generateStreakNudge() {
        guard canCreateNudge() else { return }

        let allBoards = (try? modelContext.fetch(FetchDescriptor<Board>())) ?? []
        let allNudges = (try? modelContext.fetch(FetchDescriptor<Nudge>())) ?? []

        // Check: don't create if pending/shown streak nudge already exists
        let hasPending = allNudges.contains {
            $0.type == .streak && ($0.status == .pending || $0.status == .shown)
        }
        guard !hasPending else { return }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now

        for board in allBoards {
            // Skip boards with nudges disabled
            guard board.nudgeFrequencyHours != -1 else { continue }

            let items = board.items
            guard !items.isEmpty else { continue }

            // Calculate consecutive days of engagement
            // Engagement = item updated (opened/annotated) within a board
            let streakDays = consecutiveEngagementDays(for: items)

            guard streakDays >= 3 else { continue }

            // Check cooldown: no dismissed streak nudge for this board within 30 days
            let boardItemIDs = Set(items.map(\.id))
            let recentlyDismissed = allNudges.contains { nudge in
                nudge.type == .streak &&
                nudge.status == .dismissed &&
                nudge.createdAt > thirtyDaysAgo &&
                nudge.relatedItemIDs != nil &&
                Set(nudge.relatedItemIDs ?? []).intersection(boardItemIDs).count > 0
            }
            guard !recentlyDismissed else { continue }

            let message = "You've engaged with \(board.title) \(streakDays) days in a row!"

            let nudge = Nudge(type: .streak, message: message)
            nudge.relatedItemIDs = Array(boardItemIDs.prefix(5))
            modelContext.insert(nudge)
            try? modelContext.save()
            return // Only one streak nudge at a time
        }
    }

    /// Count consecutive days ending today where at least one item was updated.
    private func consecutiveEngagementDays(for items: [Item]) -> Int {
        let calendar = Calendar.current
        var dayCount = 0
        var checkDate = calendar.startOfDay(for: .now)

        for _ in 0..<30 { // Check up to 30 days back
            let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate) ?? checkDate
            let engaged = items.contains { item in
                item.updatedAt >= checkDate && item.updatedAt < nextDay
            }
            if engaged {
                dayCount += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }

        return dayCount
    }

    // MARK: - Continue Course Nudge

    /// For each course with a next uncompleted lecture, creates a nudge like:
    /// "Lecture 5 of MIT 6.824 is next. It covers fault tolerance — you have 2 saved articles on that topic."
    private func generateContinueCourseNudge() {
        guard canCreateNudge() else { return }

        let allCourses = (try? modelContext.fetch(FetchDescriptor<Course>())) ?? []
        let allNudges = (try? modelContext.fetch(FetchDescriptor<Nudge>())) ?? []

        // Don't create if there's already a pending/shown continueCourse nudge
        let hasPending = allNudges.contains {
            $0.type == .continueCourse && ($0.status == .pending || $0.status == .shown)
        }
        guard !hasPending else { return }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now

        for course in allCourses {
            guard let nextLecture = course.nextLecture else { continue }

            // Check cooldown: no dismissed continueCourse nudge for this lecture within 30 days
            let recentlyDismissed = allNudges.contains { nudge in
                nudge.type == .continueCourse &&
                nudge.status == .dismissed &&
                nudge.createdAt > thirtyDaysAgo &&
                nudge.targetItem?.id == nextLecture.id
            }
            guard !recentlyDismissed else { continue }

            let lectureIndex = (course.lectureOrder.firstIndex(of: nextLecture.id) ?? 0) + 1
            var message = "Lecture \(lectureIndex) of \(course.title) is next."

            // Find supplementary topic overlap
            let lectureTags = nextLecture.tags
            if !lectureTags.isEmpty {
                let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
                let tagIDs = Set(lectureTags.map(\.id))
                let relatedCount = allItems.filter { item in
                    item.id != nextLecture.id &&
                    item.type != .courseLecture &&
                    item.tags.contains(where: { tagIDs.contains($0.id) })
                }.count

                if relatedCount > 0 {
                    let topicNames = lectureTags.prefix(2).map(\.name).joined(separator: " & ")
                    message += " It covers \(topicNames) — you have \(relatedCount) saved article\(relatedCount == 1 ? "" : "s") on that topic."
                }
            }

            let nudge = Nudge(type: .continueCourse, message: message, targetItem: nextLecture)
            modelContext.insert(nudge)
            try? modelContext.save()
            return // Only one course nudge at a time
        }
    }

    // MARK: - Per-Board Frequency

    /// Check if all boards for an item have nudges disabled.
    private func isBoardNudgeDisabled(for item: Item) -> Bool {
        // If item has no boards, nudges are allowed
        guard !item.boards.isEmpty else { return false }
        // If ANY board allows nudges, the item is eligible
        return item.boards.allSatisfy { $0.nudgeFrequencyHours == -1 }
    }
}
