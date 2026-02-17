import SwiftUI
import SwiftData
import CloudKit
import Combine

/// Sync status states for the UI indicator.
enum SyncStatus: Equatable {
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
/// SwiftData handles the actual sync — this service monitors account status
/// and provides UI state for the sync indicator.
@Observable
final class SyncService {
    var status: SyncStatus = .disabled

    private var accountCheckTimer: Timer?
    private var notificationObservers: [Any] = []

    init() {
        if SyncSettings.syncEnabled {
            status = .syncing
            checkAccountStatus()
            startMonitoring()
        }
    }

    deinit {
        stopMonitoring()
    }

    /// Check iCloud account availability.
    func checkAccountStatus() {
        guard SyncSettings.syncEnabled else {
            status = .disabled
            return
        }

        CKContainer.default().accountStatus { [weak self] accountStatus, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.status = .error(error.localizedDescription)
                    return
                }
                switch accountStatus {
                case .available:
                    self.status = .synced
                case .noAccount:
                    self.status = .error("No iCloud account")
                case .restricted:
                    self.status = .error("iCloud restricted")
                case .couldNotDetermine:
                    self.status = .error("Unknown status")
                case .temporarilyUnavailable:
                    self.status = .error("iCloud temporarily unavailable")
                @unknown default:
                    self.status = .error("Unknown status")
                }
            }
        }
    }

    /// Start monitoring for CloudKit account changes and sync events.
    func startMonitoring() {
        // Monitor iCloud account changes
        let accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkAccountStatus()
        }
        notificationObservers.append(accountObserver)

        // Periodically check account status (every 60 seconds)
        accountCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAccountStatus()
        }

        // Listen for remote change notifications (SwiftData/CloudKit push)
        let remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
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
        notificationObservers.append(remoteChangeObserver)
    }

    /// Stop monitoring.
    func stopMonitoring() {
        accountCheckTimer?.invalidate()
        accountCheckTimer = nil
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    /// Refresh sync state manually (e.g., when user toggles sync on).
    func refresh() {
        if SyncSettings.syncEnabled {
            status = .syncing
            checkAccountStatus()
            startMonitoring()
        } else {
            stopMonitoring()
            status = .disabled
        }
    }
}

// MARK: - Sync Settings

/// UserDefaults-backed sync configuration.
struct SyncSettings {
    private static let defaults = UserDefaults.standard

    private enum Key: String {
        case syncEnabled = "grove.sync.enabled"
    }

    /// Whether CloudKit sync is enabled. Default: false (local-only).
    static var syncEnabled: Bool {
        get { defaults.object(forKey: Key.syncEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.syncEnabled.rawValue) }
    }
}
