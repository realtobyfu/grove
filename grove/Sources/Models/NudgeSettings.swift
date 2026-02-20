import Foundation

/// Global nudge settings stored in UserDefaults.
/// Controls only the active nudge engine categories plus cadence and resurfacing queue behavior.
struct NudgeSettings: Sendable {
    private static var defaults: UserDefaults { UserDefaults.standard }

    // MARK: - Keys

    private enum Key: String {
        case resurfaceEnabled = "nudge.resurface.enabled"
        case staleInboxEnabled = "nudge.staleInbox.enabled"
        case scheduleIntervalHours = "nudge.schedule.intervalHours"
        case maxNudgesPerDay = "nudge.maxPerDay"
        case spacedResurfacingEnabled = "nudge.spacedResurfacing.enabled"
        case spacedResurfacingGlobalPause = "nudge.spacedResurfacing.globalPause"
    }

    // MARK: - Active Category Toggles

    static var resurfaceEnabled: Bool {
        get { defaults.object(forKey: Key.resurfaceEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.resurfaceEnabled.rawValue) }
    }

    static var staleInboxEnabled: Bool {
        get { defaults.object(forKey: Key.staleInboxEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.staleInboxEnabled.rawValue) }
    }

    // MARK: - Schedule

    /// How often to run the NudgeEngine, in hours. Default: 4.
    static var scheduleIntervalHours: Int {
        get {
            let val = defaults.integer(forKey: Key.scheduleIntervalHours.rawValue)
            return val > 0 ? val : 4
        }
        set { defaults.set(newValue, forKey: Key.scheduleIntervalHours.rawValue) }
    }

    /// Maximum nudges shown per day. Default: 2.
    static var maxNudgesPerDay: Int {
        get {
            let val = defaults.integer(forKey: Key.maxNudgesPerDay.rawValue)
            return val > 0 ? val : 2
        }
        set { defaults.set(newValue, forKey: Key.maxNudgesPerDay.rawValue) }
    }

    // MARK: - Spaced Resurfacing

    /// Whether spaced resurfacing is enabled (default true).
    static var spacedResurfacingEnabled: Bool {
        get { defaults.object(forKey: Key.spacedResurfacingEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.spacedResurfacingEnabled.rawValue) }
    }

    /// Global pause for all resurfacing (default false).
    static var spacedResurfacingGlobalPause: Bool {
        get { defaults.object(forKey: Key.spacedResurfacingGlobalPause.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.spacedResurfacingGlobalPause.rawValue) }
    }

    // MARK: - Helpers

    /// Active nudge generation is intentionally limited to the simplified engine.
    /// Legacy/smart/check-in categories remain in `NudgeType` only for persisted-model compatibility.
    static func isEnabled(for type: NudgeType) -> Bool {
        switch type {
        case .resurface:
            return resurfaceEnabled
        case .staleInbox:
            return staleInboxEnabled
        case .connectionPrompt, .streak, .continueCourse,
             .reflectionPrompt, .contradiction, .knowledgeGap, .synthesisPrompt,
             .dialecticalCheckIn:
            return false
        }
    }

    // MARK: - Smart Nudge Dismissed Tracking (Legacy)

    private static let smartNudgeDismissedKey = "nudge.smart.dismissed"

    /// Retained for compatibility with historical smart nudge records.
    static func recordSmartDismissal(type: NudgeType, itemID: UUID?) {
        var entries = smartDismissedEntries()
        entries.append(SmartDismissEntry(
            type: type.rawValue,
            itemID: itemID?.uuidString,
            date: Date.now.timeIntervalSince1970
        ))
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: smartNudgeDismissedKey)
        }
    }

    /// Retained for compatibility with historical smart nudge records.
    static func isSmartNudgeDismissed(type: NudgeType, itemID: UUID?) -> Bool {
        let thirtyDaysAgo = Date.now.timeIntervalSince1970 - (30 * 24 * 3600)
        return smartDismissedEntries().contains { entry in
            entry.type == type.rawValue &&
            entry.itemID == itemID?.uuidString &&
            entry.date > thirtyDaysAgo
        }
    }

    private static func smartDismissedEntries() -> [SmartDismissEntry] {
        guard let data = defaults.data(forKey: smartNudgeDismissedKey),
              let entries = try? JSONDecoder().decode([SmartDismissEntry].self, from: data)
        else { return [] }
        return entries
    }

    // MARK: - Weekly Digest Metadata (Manual-Only)

    private static let digestLastGeneratedAtKey = "digest.lastGeneratedAt"

    /// Timestamp of the last digest generation (TimeInterval since 1970). Default: 0 (never).
    static var digestLastGeneratedAt: TimeInterval {
        get { defaults.double(forKey: digestLastGeneratedAtKey) }
        set { defaults.set(newValue, forKey: digestLastGeneratedAtKey) }
    }

    // MARK: - Analytics Keys

    private static let analyticsKey = "nudge.analytics"

    /// Nudge analytics: tracks count of acted-on and dismissed per type.
    /// Stored as [String: Int] where keys are like "resurface.actedOn", "resurface.dismissed".
    static func recordAction(type: NudgeType, actedOn: Bool) {
        let suffix = actedOn ? "actedOn" : "dismissed"
        let key = "\(analyticsKey).\(type.rawValue).\(suffix)"
        let current = defaults.integer(forKey: key)
        defaults.set(current + 1, forKey: key)
    }

    static func analyticsCount(type: NudgeType, actedOn: Bool) -> Int {
        let suffix = actedOn ? "actedOn" : "dismissed"
        let key = "\(analyticsKey).\(type.rawValue).\(suffix)"
        return defaults.integer(forKey: key)
    }
}

// MARK: - Smart Dismiss Entry

private struct SmartDismissEntry: Codable {
    let type: String
    let itemID: String?
    let date: TimeInterval
}
