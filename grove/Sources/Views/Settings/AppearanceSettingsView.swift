import SwiftUI

/// Settings view for app appearance preferences.
struct AppearanceSettingsView: View {
    @Environment(OnboardingService.self) private var onboarding
    @State private var monochromeCoverImages = AppearanceSettings.monochromeCoverImages
    @State private var defaultMarkdownEditorMode = AppearanceSettings.defaultMarkdownEditorMode

    var body: some View {
        Form {
            Section("Markdown Editor") {
                Picker("Default editing mode", selection: $defaultMarkdownEditorMode) {
                    ForEach(MarkdownEditorMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: defaultMarkdownEditorMode) { _, newValue in
                    AppearanceSettings.defaultMarkdownEditorMode = newValue
                }

                Text("New editors open in this mode by default. You can still switch modes inside each editor.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }

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
