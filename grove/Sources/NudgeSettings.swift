import Foundation

/// Global nudge settings stored in UserDefaults.
/// Controls which nudge categories are enabled, frequency, and daily limits.
struct NudgeSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key: String {
        case resurfaceEnabled = "nudge.resurface.enabled"
        case staleInboxEnabled = "nudge.staleInbox.enabled"
        case connectionPromptEnabled = "nudge.connectionPrompt.enabled"
        case streakEnabled = "nudge.streak.enabled"
        case scheduleIntervalHours = "nudge.schedule.intervalHours"
        case maxNudgesPerDay = "nudge.maxPerDay"
    }

    // MARK: - Type Toggles

    static var resurfaceEnabled: Bool {
        get { defaults.object(forKey: Key.resurfaceEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.resurfaceEnabled.rawValue) }
    }

    static var staleInboxEnabled: Bool {
        get { defaults.object(forKey: Key.staleInboxEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.staleInboxEnabled.rawValue) }
    }

    static var connectionPromptEnabled: Bool {
        get { defaults.object(forKey: Key.connectionPromptEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.connectionPromptEnabled.rawValue) }
    }

    static var streakEnabled: Bool {
        get { defaults.object(forKey: Key.streakEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.streakEnabled.rawValue) }
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

    // MARK: - Helpers

    static func isEnabled(for type: NudgeType) -> Bool {
        switch type {
        case .resurface: return resurfaceEnabled
        case .staleInbox: return staleInboxEnabled
        case .connectionPrompt: return connectionPromptEnabled
        case .streak: return streakEnabled
        }
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
