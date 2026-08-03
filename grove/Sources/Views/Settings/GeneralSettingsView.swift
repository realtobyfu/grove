#if os(macOS)
import AppKit
#endif
import SwiftUI

/// Settings view for general app preferences: appearance, onboarding, and feedback.
struct GeneralSettingsView: View {
    @Environment(OnboardingService.self) private var onboarding
    @Environment(\.openURL) private var openURL
    @State private var monochromeCoverImages = AppearanceSettings.monochromeCoverImages

    var body: some View {
        Form {
            Section("Cover Images") {
                Toggle("Render cover images in black and white", isOn: $monochromeCoverImages)
                    .onChange(of: monochromeCoverImages) { _, newValue in
                        AppearanceSettings.monochromeCoverImages = newValue
                    }

                Text("Turn this off to display cover images in full color.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Onboarding") {
                Button("Replay Onboarding") {
                    onboarding.presentReplay()
                }
                .tint(Color.textPrimary)
                .buttonStyle(.borderedProminent)

                Text("Reopen the guided setup flow from any state.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
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

                Text("Opens your default email client with a pre-filled message to the developer.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
    }
}
