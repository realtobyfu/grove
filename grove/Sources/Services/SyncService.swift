import SwiftUI
import SwiftData

/// Sync status states for the UI indicator.
enum SyncStatus: Equatable, Sendable {
    case disabled
    case synced
    case syncing
    case error(String)

    var iconName: String {
        switch self {
        case .disabled: return "icloud.slash"
        case .synced: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .error: return "exclamationmark.icloud"
        }
    }

    var label: String {
        switch self {
        case .disabled: return "Sync Disabled"
        case .synced: return "Synced"
        case .syncing: return "Syncing..."
        case .error(let msg): return "Sync Error: \(msg)"
        }
    }
}

/// Manages CloudKit sync state and monitoring.
/// SwiftData handles the actual sync — this service monitors sync events
/// and provides UI state for the sync indicator.
@MainActor
@Observable
final class SyncService {
    var status: SyncStatus = .disabled

    private var monitoringTasks: [Task<Void, Never>] = []

    init() {
        if SyncSettings.syncEnabled {
            status = .synced
            startMonitoring()
        }
    }

    /// Start monitoring for SwiftData/CloudKit sync events.
    func startMonitoring() {
        let remoteChangeTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification) {
                guard let self else { return }
                if let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event {
                    switch event.type {
                    case .setup:
                        self.status = .syncing
                    case .import:
                        self.status = event.endDate != nil ? .synced : .syncing
                    case .export:
                        self.status = event.endDate != nil ? .synced : .syncing
                    @unknown default:
                        break
                    }
                    if let error = event.error {
                        self.status = .error(error.localizedDescription)
                    }
                }
            }
        }
        monitoringTasks.append(remoteChangeTask)
    }

    /// Stop monitoring.
    func stopMonitoring() {
        for task in monitoringTasks {
            task.cancel()
        }
        monitoringTasks.removeAll()
    }

    /// Refresh sync state manually.
    func refresh() {
        if SyncSettings.syncEnabled {
            status = .synced
            startMonitoring()
        } else {
            stopMonitoring()
            status = .disabled
        }
    }
}

// MARK: - Sync Settings

/// UserDefaults-backed sync configuration.
struct SyncSettings: Sendable {
    private static var defaults: UserDefaults { UserDefaults.standard }

    private enum Key: String {
        case syncEnabled = "grove.sync.enabled"
    }

    /// Whether CloudKit sync is enabled. Default: false (local-only).
    static var syncEnabled: Bool {
        get { defaults.object(forKey: Key.syncEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.syncEnabled.rawValue) }
    }
}
