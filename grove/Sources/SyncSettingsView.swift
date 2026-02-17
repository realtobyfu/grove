import SwiftUI
import CloudKit

/// Settings view for CloudKit sync configuration.
struct SyncSettingsView: View {
    @State private var syncEnabled = SyncSettings.syncEnabled
    @State private var accountStatusText = "Checking..."
    @State private var showRestartAlert = false

    var body: some View {
        Form {
            Section("iCloud Sync") {
                Toggle("Enable CloudKit Sync", isOn: $syncEnabled)
                    .onChange(of: syncEnabled) { _, newValue in
                        SyncSettings.syncEnabled = newValue
                        showRestartAlert = true
                    }

                Text("When enabled, all your items, boards, tags, connections, annotations, and nudges sync across devices via iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if syncEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("Changing sync requires restarting Grove to take effect.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Account Status") {
                HStack(spacing: 8) {
                    Image(systemName: syncEnabled ? "icloud" : "icloud.slash")
                        .foregroundStyle(syncEnabled ? .blue : .secondary)
                    Text(accountStatusText)
                        .font(.subheadline)
                }

                if syncEnabled {
                    Button("Check Account Status") {
                        checkAccount()
                    }
                    .controlSize(.small)
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
        .onAppear {
            checkAccount()
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("OK") { }
        } message: {
            Text("Please restart Grove for the sync setting to take effect.")
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func checkAccount() {
        guard syncEnabled else {
            accountStatusText = "Sync is disabled (local-only mode)"
            return
        }

        accountStatusText = "Checking..."
        CKContainer.default().accountStatus { status, error in
            DispatchQueue.main.async {
                if let error {
                    accountStatusText = "Error: \(error.localizedDescription)"
                    return
                }
                switch status {
                case .available:
                    accountStatusText = "iCloud account available"
                case .noAccount:
                    accountStatusText = "No iCloud account signed in"
                case .restricted:
                    accountStatusText = "iCloud access restricted"
                case .couldNotDetermine:
                    accountStatusText = "Could not determine account status"
                case .temporarilyUnavailable:
                    accountStatusText = "iCloud temporarily unavailable"
                @unknown default:
                    accountStatusText = "Unknown status"
                }
            }
        }
    }
}
