import SwiftUI
import SwiftData

/// Settings view for configuring nudge behavior.
/// Accessible from the app's Settings window.
struct NudgeSettingsView: View {
    @State private var resurfaceEnabled = NudgeSettings.resurfaceEnabled
    @State private var staleInboxEnabled = NudgeSettings.staleInboxEnabled
    @State private var connectionPromptEnabled = NudgeSettings.connectionPromptEnabled
    @State private var streakEnabled = NudgeSettings.streakEnabled
    @State private var scheduleIntervalHours = NudgeSettings.scheduleIntervalHours
    @State private var maxNudgesPerDay = NudgeSettings.maxNudgesPerDay

    private static let intervalOptions: [(label: String, value: Int)] = [
        ("Every 2 Hours", 2),
        ("Every 4 Hours", 4),
        ("Every 8 Hours", 8),
        ("Every 12 Hours", 12),
        ("Once a Day", 24)
    ]

    var body: some View {
        Form {
            Section("Nudge Categories") {
                Toggle("Resurface", isOn: $resurfaceEnabled)
                    .onChange(of: resurfaceEnabled) { _, newValue in
                        NudgeSettings.resurfaceEnabled = newValue
                    }
                Text("Reminds you about saved items you haven't revisited.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Stale Inbox", isOn: $staleInboxEnabled)
                    .onChange(of: staleInboxEnabled) { _, newValue in
                        NudgeSettings.staleInboxEnabled = newValue
                    }
                Text("Alerts when inbox items pile up without triage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Connection Prompts", isOn: $connectionPromptEnabled)
                    .onChange(of: connectionPromptEnabled) { _, newValue in
                        NudgeSettings.connectionPromptEnabled = newValue
                    }
                Text("Suggests writing a synthesis note when you add multiple items on the same topic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Streaks", isOn: $streakEnabled)
                    .onChange(of: streakEnabled) { _, newValue in
                        NudgeSettings.streakEnabled = newValue
                    }
                Text("Celebrates consecutive days of engagement with a board.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Schedule") {
                Picker("Check Frequency", selection: $scheduleIntervalHours) {
                    ForEach(Self.intervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .onChange(of: scheduleIntervalHours) { _, newValue in
                    NudgeSettings.scheduleIntervalHours = newValue
                }

                Stepper("Max per day: \(maxNudgesPerDay)", value: $maxNudgesPerDay, in: 1...10)
                    .onChange(of: maxNudgesPerDay) { _, newValue in
                        NudgeSettings.maxNudgesPerDay = newValue
                    }
                Text("Users with high engagement (3+ acted-on nudges in 7 days) may see more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Analytics") {
                analyticsRow(type: .resurface, label: "Resurface")
                analyticsRow(type: .staleInbox, label: "Stale Inbox")
                analyticsRow(type: .connectionPrompt, label: "Connection Prompts")
                analyticsRow(type: .streak, label: "Streaks")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
    }

    private func analyticsRow(type: NudgeType, label: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            let actedOn = NudgeSettings.analyticsCount(type: type, actedOn: true)
            let dismissed = NudgeSettings.analyticsCount(type: type, actedOn: false)
            Text("Acted: \(actedOn)")
                .font(.caption)
                .foregroundStyle(.green)
            Text("Dismissed: \(dismissed)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
