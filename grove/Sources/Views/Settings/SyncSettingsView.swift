import SwiftUI

/// Settings view for CloudKit sync configuration.
/// On macOS these sections live inside AccountSettingsView; iOS presents this view directly.
struct SyncSettingsView: View {
    var body: some View {
        Form {
            SyncSettingsSections()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// Form sections for CloudKit sync, embeddable in any Form.
struct SyncSettingsSections: View {
    @Environment(SyncService.self) private var syncService
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @State private var syncEnabled = SyncSettings.syncEnabled
    @State private var showRestartAlert = false
    @State private var paywallPresentation: PaywallPresentation?

    var body: some View {
        Group {
            Section("iCloud Sync") {
                Toggle("Keep my library in iCloud", isOn: $syncEnabled)
                    .disabled(!entitlement.hasAccess(to: .sync))
                    .onChange(of: syncEnabled) { _, newValue in
                        guard newValue else {
                            SyncSettings.syncEnabled = false
                            showRestartAlert = true
                            return
                        }

                        SyncSettings.syncEnabled = newValue
                        showRestartAlert = true
                    }

                if entitlement.hasAccess(to: .sync) {
                    Text("Sync your library, flashcards, reviews, and focus across devices.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "lock")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                        Text("Cross-device sync is available with Pro.")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Button("Unlock Pro") {
                        paywallPresentation = paywallCoordinator.present(
                            feature: .sync,
                            source: .syncSettings,
                            pendingAction: {
                                syncEnabled = true
                                SyncSettings.syncEnabled = true
                                showRestartAlert = true
                            }
                        )
                    }
                    .tint(Color.textPrimary)
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Color.textPrimary)
                        .font(.groveBodySmall)
                    Text("Restart Grove after changing sync.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textPrimary)
                        .fontWeight(.semibold)
                }
            }

            Section("Status") {
                HStack(spacing: 8) {
                    Image(systemName: syncEnabled ? "icloud" : "icloud.slash")
                        .foregroundStyle(syncEnabled ? Color.textPrimary : Color.textSecondary)
                    Text(syncEnabled != syncService.isSyncConfigured
                         ? "Saved locally. Restart to apply sync settings."
                         : syncService.status.label)
                        .font(.groveBodySecondary)
                }
                if let completedAt = syncService.lastCompletedAt {
                    Text("Last iCloud activity: \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Section("How Sync Works") {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow(icon: "arrow.triangle.2.circlepath", text: "Syncs automatically when connected")
                    infoRow(icon: "wifi.slash", text: "Offline changes sync later")
                    infoRow(icon: "arrow.merge", text: "Each device’s reviews are preserved")
                    infoRow(icon: "clock", text: "Updates may reach each device at different times")
                    infoRow(icon: "lock.shield", text: "Uses your private iCloud storage")
                }
            }
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("OK") { }
        } message: {
            Text("Restart Grove to apply sync settings.")
        }
        .sheet(item: $paywallPresentation) { presentation in
            ProPaywallView(presentation: presentation)
        }
        .onAppear {
            if !entitlement.hasAccess(to: .sync), syncEnabled {
                syncEnabled = false
                SyncSettings.syncEnabled = false
            }
        }
        .onChange(of: entitlement.state.updatedAt) {
            syncEnabled = SyncSettings.syncEnabled
            if !entitlement.hasAccess(to: .sync), syncEnabled {
                syncEnabled = false
                SyncSettings.syncEnabled = false
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 16)
            Text(text)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
