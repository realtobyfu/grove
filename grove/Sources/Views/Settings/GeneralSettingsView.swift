#if os(macOS)
import AppKit
#endif
import SwiftUI

/// Settings view for general app preferences: appearance, reminders, onboarding, and feedback.
struct GeneralSettingsView: View {
    @Environment(OnboardingService.self) private var onboarding
    @Environment(\.openURL) private var openURL
    @State private var monochromeCoverImages = AppearanceSettings.monochromeCoverImages
    @State private var notificationsEnabled = NudgeSettings.notificationsEnabled
    @State private var staleInboxEnabled = NudgeSettings.staleInboxEnabled

    var body: some View {
        Form {
            Section("Cover Images") {
                Toggle("Black and white images", isOn: $monochromeCoverImages)
                    .onChange(of: monochromeCoverImages) { _, newValue in
                        AppearanceSettings.monochromeCoverImages = newValue
                    }

            }

            Section("Reminders") {
                Toggle("System Notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        updateNotificationPreference(newValue)
                    }

                Text("When off, reminders appear only inside Today.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)

                Toggle("Stale inbox reminders", isOn: $staleInboxEnabled)
                    .onChange(of: staleInboxEnabled) { _, newValue in
                        NudgeSettings.staleInboxEnabled = newValue
                    }
            }

            Section("Onboarding") {
                Button("Replay setup") {
                    onboarding.presentReplay()
                }
                .tint(Color.textPrimary)
                .buttonStyle(.borderedProminent)

            }

            Section("Feedback") {
                Button("Send Feedback") {
                    let subject = "Grove Feedback"
                        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Grove%20Feedback"
                    if let url = URL(string: "mailto:3tobiasfu@gmail.com?subject=\(subject)") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        openURL(url)
                        #endif
                    }
                }
                .tint(Color.textPrimary)
                .buttonStyle(.bordered)

                Text("Opens your email app.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
    }

    /// Permission is requested only on an explicit turn-on; the toggle snaps
    /// back to the effective value when the system denies it.
    private func updateNotificationPreference(_ enabled: Bool) {
        Task {
            let effectiveValue = await NudgeNotificationService.shared
                .setNotificationsEnabled(enabled)
            if notificationsEnabled != effectiveValue {
                notificationsEnabled = effectiveValue
            }
        }
    }
}
