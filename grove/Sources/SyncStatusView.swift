import SwiftUI

/// Toolbar indicator showing current CloudKit sync status.
struct SyncStatusView: View {
    var syncService: SyncService

    var body: some View {
        if SyncSettings.syncEnabled {
            HStack(spacing: 4) {
                statusIcon
                    .font(.caption)
                    .symbolEffect(.pulse, isActive: syncService.status == .syncing)
            }
            .help(syncService.status.label)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch syncService.status {
        case .disabled:
            Image(systemName: SyncStatus.disabled.iconName)
                .foregroundStyle(.secondary)
        case .synced:
            Image(systemName: SyncStatus.synced.iconName)
                .foregroundStyle(.green)
        case .syncing:
            Image(systemName: SyncStatus.syncing.iconName)
                .foregroundStyle(.blue)
        case .error:
            Image(systemName: SyncStatus.error("").iconName)
                .foregroundStyle(.orange)
        }
    }
}
