import SwiftUI
import SwiftData
import CloudKit
import Combine

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
/// SwiftData handles the actual sync — this service monitors account status
/// and provides UI state for the sync indicator.
@MainActor
@Observable
final class SyncService {
    var status: SyncStatus = .disabled

    private var accountCheckTimer: Timer?
    private var monitoringTasks: [Task<Void, Never>] = []

    init() {
        if SyncSettings.syncEnabled {
            status = .syncing
            Task {
                await checkAccountStatus()
            }
            startMonitoring()
        }
    }

    /// Check iCloud account availability.
    func checkAccountStatus() async {
        guard SyncSettings.syncEnabled else {
            status = .disabled
            return
        }

        do {
            let accountStatus = try await CKContainer.default().accountStatus()
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
        } catch {
            self.status = .error(error.localizedDescription)
        }
    }

    /// Start monitoring for CloudKit account changes and sync events.
    func startMonitoring() {
        // Monitor iCloud account changes via async sequence
        let accountTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard let self else { return }
                await self.checkAccountStatus()
            }
        }
        monitoringTasks.append(accountTask)

        // Periodically check account status (every 60 seconds)
        accountCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.checkAccountStatus()
            }
        }

        // Listen for remote change notifications (SwiftData/CloudKit push)
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
        accountCheckTimer?.invalidate()
        accountCheckTimer = nil
        for task in monitoringTasks {
            task.cancel()
        }
        monitoringTasks.removeAll()
    }

    /// Refresh sync state manually (e.g., when user toggles sync on).
    func refresh() {
        if SyncSettings.syncEnabled {
            status = .syncing
            Task {
                await checkAccountStatus()
            }
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
    private static nonisolated(unsafe) let defaults = UserDefaults.standard

    private enum Key: String {
        case syncEnabled = "grove.sync.enabled"
    }

    /// Whether CloudKit sync is enabled. Default: false (local-only).
    static var syncEnabled: Bool {
        get { defaults.object(forKey: Key.syncEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.syncEnabled.rawValue) }
    }
}
