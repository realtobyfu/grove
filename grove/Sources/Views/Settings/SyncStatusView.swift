import SwiftUI

/// Toolbar indicator showing current CloudKit sync status.
struct SyncStatusView: View {
    var syncService: SyncService

    var body: some View {
        if SyncSettings.syncEnabled {
            HStack(spacing: 4) {
                statusIcon
                    .font(.groveMeta)
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
                .foregroundStyle(Color.textTertiary)
        case .waiting:
            Image(systemName: SyncStatus.waiting.iconName)
                .foregroundStyle(Color.textSecondary)
        case .synced:
            Image(systemName: SyncStatus.synced.iconName)
                .foregroundStyle(Color.textPrimary)
        case .syncing:
            Image(systemName: SyncStatus.syncing.iconName)
                .foregroundStyle(Color.textSecondary)
        case .error:
            Image(systemName: SyncStatus.error("").iconName)
                .foregroundStyle(Color.textPrimary)
        }
    }
}
