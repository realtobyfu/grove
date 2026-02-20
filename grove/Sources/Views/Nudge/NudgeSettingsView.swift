import SwiftUI
import SwiftData

/// Settings view for configuring nudge behavior.
/// Accessible from the app's Settings window.
struct NudgeSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var resurfaceEnabled = NudgeSettings.resurfaceEnabled
    @State private var staleInboxEnabled = NudgeSettings.staleInboxEnabled
    @State private var scheduleIntervalHours = NudgeSettings.scheduleIntervalHours
    @State private var maxNudgesPerDay = NudgeSettings.maxNudgesPerDay
    @State private var spacedResurfacingEnabled = NudgeSettings.spacedResurfacingEnabled
    @State private var globalResurfacingPause = NudgeSettings.spacedResurfacingGlobalPause
    @State private var queueStats: ResurfacingService.QueueStats?
    @State private var showAdvancedDetails = false

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

                Toggle("Stale Inbox", isOn: $staleInboxEnabled)
                    .onChange(of: staleInboxEnabled) { _, newValue in
                        NudgeSettings.staleInboxEnabled = newValue
                    }

                Text("Only active nudge categories are shown here.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Cadence") {
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

                Text("High engagement may temporarily exceed this cap.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Weekly Digest") {
                Text("Weekly Digest is manual-only and not part of the active nudge engine.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)

                digestStatusText
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Advanced") {
                DisclosureGroup("Resurfacing queue and analytics", isExpanded: $showAdvancedDetails) {
                    Toggle("Enable spaced resurfacing", isOn: $spacedResurfacingEnabled)
                        .onChange(of: spacedResurfacingEnabled) { _, newValue in
                            NudgeSettings.spacedResurfacingEnabled = newValue
                        }

                    Toggle("Pause all resurfacing", isOn: $globalResurfacingPause)
                        .onChange(of: globalResurfacingPause) { _, newValue in
                            NudgeSettings.spacedResurfacingGlobalPause = newValue
                        }

                    Text("Items with annotations or connections enter a resurfacing queue.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)

                    if let stats = queueStats {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Queue")
                                .font(.groveBadge)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.textSecondary)

                            HStack(spacing: Spacing.lg) {
                                statBadge(value: stats.totalInQueue, label: "In Queue")
                                statBadge(value: stats.upcoming, label: "Upcoming")
                                statBadge(value: stats.overdue, label: "Overdue")
                                statBadge(value: stats.paused, label: "Paused")
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    Text("Analytics")
                        .font(.groveBadge)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)

                    analyticsRow(type: .resurface, label: "Resurface")
                    analyticsRow(type: .staleInbox, label: "Stale Inbox")
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
        .onAppear {
            loadQueueStats()
        }
        .onChange(of: showAdvancedDetails) { _, expanded in
            if expanded {
                loadQueueStats()
            }
        }
    }

    private func statBadge(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.groveItemTitle)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.groveBadge)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var digestStatusText: Text {
        let lastGenerated = NudgeSettings.digestLastGeneratedAt
        if lastGenerated > 0 {
            let date = Date(timeIntervalSince1970: lastGenerated)
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return Text("Last generated \(formatter.localizedString(for: date, relativeTo: .now))")
        } else {
            return Text("No digest generated yet.")
        }
    }

    private func loadQueueStats() {
        let service = ResurfacingService(modelContext: modelContext)
        queueStats = service.queueStats()
    }

    private func analyticsRow(type: NudgeType, label: String) -> some View {
        HStack {
            Text(label)
                .font(.groveBody)
            Spacer()
            let actedOn = NudgeSettings.analyticsCount(type: type, actedOn: true)
            let dismissed = NudgeSettings.analyticsCount(type: type, actedOn: false)
            Text("Acted: \(actedOn)")
                .font(.groveMeta)
                .fontWeight(.medium)
                .foregroundStyle(Color.textPrimary)
            Text("Dismissed: \(dismissed)")
                .font(.groveMeta)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
