import SwiftUI
import SwiftData
import CoreData

/// Sync status states for the UI indicator.
enum SyncStatus: Equatable, Sendable {
    case disabled
    case waiting
    case synced
    case syncing
    case error(String)

    var iconName: String {
        switch self {
        case .disabled: return "icloud.slash"
        case .waiting: return "icloud"
        case .synced: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .error: return "exclamationmark.icloud"
        }
    }

    var label: String {
        switch self {
        case .disabled: return "Saved on this device"
        case .waiting: return "Waiting for iCloud"
        case .synced: return "Last iCloud update completed"
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
    private(set) var status: SyncStatus = .disabled
    let isSyncConfigured: Bool
    private(set) var lastCompletedAt: Date?

    private var monitoringTasks: [Task<Void, Never>] = []
    private var activeEventIDs: Set<UUID> = []
    private var lastEventError: String?

    init(syncEnabled: Bool = SyncSettings.syncEnabled, startsMonitoring: Bool = true) {
        isSyncConfigured = syncEnabled
        if syncEnabled {
            status = .waiting
            if startsMonitoring { startMonitoring() }
        }
    }

    /// Start monitoring for SwiftData/CloudKit sync events.
    func startMonitoring() {
        guard isSyncConfigured, monitoringTasks.isEmpty else { return }
        let remoteChangeTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification) {
                guard let self else { return }
                if let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event {
                    self.recordEvent(
                        id: event.identifier,
                        completedAt: event.endDate,
                        errorDescription: event.error?.localizedDescription,
                        // Setup completion is not evidence that data was transferred.
                        isDataTransfer: event.type == .import || event.type == .export
                    )
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
        activeEventIDs.removeAll()
    }

    /// Refresh sync state manually.
    func refresh() {
        if isSyncConfigured {
            // Foregrounding must not erase an error or an in-flight transfer.
            if lastEventError == nil, activeEventIDs.isEmpty, lastCompletedAt == nil {
                status = .waiting
            }
            startMonitoring()
        } else {
            stopMonitoring()
            status = .disabled
        }
    }

    /// An event acknowledges this store's activity, not delivery to every other device.
    func recordEvent(
        id: UUID,
        completedAt: Date?,
        errorDescription: String?,
        isDataTransfer: Bool = true
    ) {
        guard isSyncConfigured else { return }
        if let completedAt {
            activeEventIDs.remove(id)
            if let errorDescription {
                lastEventError = errorDescription
            } else if isDataTransfer {
                lastCompletedAt = max(lastCompletedAt ?? .distantPast, completedAt)
                lastEventError = nil
            }
        } else {
            activeEventIDs.insert(id)
            if let errorDescription { lastEventError = errorDescription }
        }
        if let lastEventError {
            status = .error(lastEventError)
        } else if !activeEventIDs.isEmpty {
            status = .syncing
        } else {
            status = lastCompletedAt == nil ? .waiting : .synced
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
