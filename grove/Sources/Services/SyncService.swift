import SwiftUI
import SQLiteData

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
/// SQLiteData's `SyncEngine` does the actual sync — this service watches it and
/// provides UI state for the sync indicator.
@MainActor
@Observable
final class SyncService {
    private(set) var status: SyncStatus = .disabled
    let isSyncConfigured: Bool
    private(set) var lastCompletedAt: Date?

    private let engine: SyncEngine?
    private var monitoringTasks: [Task<Void, Never>] = []
    private var activeEventIDs: Set<UUID> = []
    private var lastEventError: String?

    init(
        engine: SyncEngine? = nil,
        syncEnabled: Bool = SyncSettings.syncEnabled,
        startupError: String? = nil,
        startsMonitoring: Bool = true
    ) {
        self.engine = engine
        isSyncConfigured = syncEnabled
        lastEventError = startupError
        if syncEnabled {
            status = startupError.map(SyncStatus.error) ?? .waiting
            if startsMonitoring { startMonitoring() }
        }
    }

    /// Start watching the sync engine. Each stretch of synchronizing counts as
    /// one event.
    func startMonitoring() {
        guard isSyncConfigured, let engine, monitoringTasks.isEmpty else { return }
        let monitor = Task { [weak self] in
            var activeEvent: UUID?
            while !Task.isCancelled {
                let isSynchronizing = await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = engine.isSynchronizing
                    } onChange: {
                        continuation.resume(returning: engine.isSynchronizing)
                    }
                }
                guard let self else { return }
                if isSynchronizing, activeEvent == nil {
                    let event = UUID()
                    activeEvent = event
                    self.recordEvent(id: event, completedAt: nil, errorDescription: nil)
                } else if !isSynchronizing, let event = activeEvent {
                    activeEvent = nil
                    self.recordEvent(id: event, completedAt: .now, errorDescription: nil)
                }
            }
        }
        monitoringTasks.append(monitor)
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
        // Not "grove.sync.enabled": that one is true wherever SwiftData sync was
        // on, and reusing it would upload the whole library in a new format the
        // first time a signed build launched.
        case syncEnabled = "grove.sqlitedata.sync.enabled"
    }

    /// Whether CloudKit sync is enabled. Default: false (local-only).
    static var syncEnabled: Bool {
        get { defaults.object(forKey: Key.syncEnabled.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.syncEnabled.rawValue) }
    }
}
