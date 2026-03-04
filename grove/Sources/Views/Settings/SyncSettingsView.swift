import SwiftUI

/// Settings view for CloudKit sync configuration.
struct SyncSettingsView: View {
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @State private var syncEnabled = SyncSettings.syncEnabled
    @State private var showRestartAlert = false
    @State private var paywallPresentation: PaywallPresentation?

    var body: some View {
        Form {
            Section("iCloud Sync") {
                Toggle("Enable CloudKit Sync", isOn: $syncEnabled)
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
                    Text("When enabled, all your items, boards, tags, connections, annotations, and nudges sync across devices via iCloud.")
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
                    Text("Changing sync requires restarting Grove to take effect.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textPrimary)
                        .fontWeight(.semibold)
                }
            }

            Section("Status") {
                HStack(spacing: 8) {
                    Image(systemName: syncEnabled ? "icloud" : "icloud.slash")
                        .foregroundStyle(syncEnabled ? Color.textPrimary : Color.textSecondary)
                    Text(syncEnabled ? "Sync enabled — data syncs automatically" : entitlement.hasAccess(to: .sync) ? "Local-only mode" : "Local-only mode (Sync requires Pro)")
                        .font(.groveBodySecondary)
                }
            }

            Section("How Sync Works") {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow(icon: "arrow.triangle.2.circlepath", text: "Data syncs automatically in the background")
                    infoRow(icon: "wifi.slash", text: "Works offline — changes queue and sync when connected")
                    infoRow(icon: "arrow.merge", text: "Conflicts resolved: last-write-wins for fields, merge for relationships")
                    infoRow(icon: "iphone", text: "Future-ready for iOS companion app")
                    infoRow(icon: "lock.shield", text: "All data stays in your private iCloud container")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("OK") { }
        } message: {
            Text("Please restart Grove for the sync setting to take effect.")
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
