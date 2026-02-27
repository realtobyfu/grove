#if os(macOS)
import AppKit
#endif
import Foundation
import UserNotifications

private enum NudgeNotificationRouting {
    static let categoryIdentifier = "grove.nudge"
    static let openActionIdentifier = "grove.nudge.open"
    static let dismissActionIdentifier = "grove.nudge.dismiss"
    static let nudgeIDUserInfoKey = "nudgeID"

    static func notificationIdentifier(for nudgeID: UUID) -> String {
        "grove.nudge.\(nudgeID.uuidString)"
    }

    static func isNudgeNotification(identifier: String) -> Bool {
        identifier.hasPrefix("grove.nudge.")
    }

    static func nudgeID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let rawID = userInfo[nudgeIDUserInfoKey] as? String else { return nil }
        return UUID(uuidString: rawID)
    }
}

@MainActor
final class NudgeNotificationService: NSObject {
    static let shared = NudgeNotificationService()

    private let center = UNUserNotificationCenter.current()
    private var isConfigured = false

    private override init() {
        super.init()
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        center.delegate = self
        registerNudgeCategory()

        Task { [weak self] in
            await self?.requestAuthorizationIfNeeded()
        }
    }

    func schedule(for nudge: Nudge) {
        guard nudge.status == .pending else { return }

        let identifier = NudgeNotificationRouting.notificationIdentifier(for: nudge.id)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content(for: nudge),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(request)
    }

    func cancel(for nudgeID: UUID) {
        let identifier = NudgeNotificationRouting.notificationIdentifier(for: nudgeID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func content(for nudge: Nudge) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title(for: nudge.type)
        content.body = nudge.message
        content.sound = .default
        content.categoryIdentifier = NudgeNotificationRouting.categoryIdentifier
        content.userInfo = [NudgeNotificationRouting.nudgeIDUserInfoKey: nudge.id.uuidString]
        return content
    }

    private func title(for type: NudgeType) -> String {
        switch type {
        case .resurface:
            return "Review Reminder"
        case .staleInbox:
            return "Inbox Reminder"
        case .dialecticalCheckIn:
            return "Check-In"
        case .connectionPrompt, .streak, .continueCourse,
             .reflectionPrompt, .contradiction, .knowledgeGap, .synthesisPrompt:
            return "Grove Reminder"
        }
    }

    private func registerNudgeCategory() {
        let openAction = UNNotificationAction(
            identifier: NudgeNotificationRouting.openActionIdentifier,
            title: "Open",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: NudgeNotificationRouting.dismissActionIdentifier,
            title: "Dismiss",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: NudgeNotificationRouting.categoryIdentifier,
            actions: [openAction, dismissAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    private func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }
}

extension NudgeNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard NudgeNotificationRouting.isNudgeNotification(identifier: notification.request.identifier) else {
            return []
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard NudgeNotificationRouting.isNudgeNotification(identifier: response.notification.request.identifier),
              let nudgeID = NudgeNotificationRouting.nudgeID(from: response.notification.request.content.userInfo)
        else {
            return
        }
        let actionIdentifier = response.actionIdentifier

        await MainActor.run {
            #if os(macOS)
            NSApplication.shared.activate(ignoringOtherApps: true)
            #endif

            switch actionIdentifier {
            case NudgeNotificationRouting.dismissActionIdentifier:
                NotificationCenter.default.post(name: .groveDismissNudgeNotification, object: nudgeID)
            case NudgeNotificationRouting.openActionIdentifier, UNNotificationDefaultActionIdentifier:
                NotificationCenter.default.post(name: .groveOpenNudgeNotification, object: nudgeID)
            default:
                break
            }
        }
    }
}
