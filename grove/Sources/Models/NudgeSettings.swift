import Foundation

/// Global nudge settings stored in UserDefaults.
/// Covers the one active nudge category (stale inbox) and system-notification delivery.
struct NudgeSettings: Sendable {
    private static var defaults: UserDefaults { UserDefaults.standard }

    // MARK: - Keys

    private enum Key: String {
        case staleInboxEnabled = "nudge.staleInbox.enabled"
        case notificationsEnabled = "nudge.notifications.enabled"
    }

    // MARK: - Active Category Toggles

    static var staleInboxEnabled: Bool {
        get { defaults.object(forKey: Key.staleInboxEnabled.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.staleInboxEnabled.rawValue) }
    }

    /// System notifications are opt-in. In-app Today nudges work independently.
    static var notificationsEnabled: Bool {
        get { defaults.object(forKey: Key.notificationsEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled.rawValue) }
    }
}
