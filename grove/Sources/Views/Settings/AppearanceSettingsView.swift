import SwiftUI

/// Settings view for app appearance preferences.
struct AppearanceSettingsView: View {
    @Environment(OnboardingService.self) private var onboarding
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
                .buttonStyle(.borderedProminent)

                Text("Reopen the guided setup flow from any state.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
    }
}
