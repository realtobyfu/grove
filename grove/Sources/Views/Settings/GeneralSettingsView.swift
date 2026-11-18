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
            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { ThemeStore.shared.theme },
                    set: { ThemeStore.shared.select($0) }
                )) {
                    ForEach(GroveTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                Text(ThemeStore.shared.theme.summary)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Cover Images") {
                Toggle("Black and white images", isOn: $monochromeCoverImages)
                    .onChange(of: monochromeCoverImages) { _, newValue in
                        AppearanceSettings.monochromeCoverImages = newValue
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
}
