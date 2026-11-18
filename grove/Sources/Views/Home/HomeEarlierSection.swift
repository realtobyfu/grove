import SwiftUI

/// "Earlier today" on the Today page: what in the library was touched today,
/// newest first — a time, a title, and what the model can truthfully say
/// happened (`TodayDigest.Touch`). With nothing to list, the section renders
/// nothing at all.
struct HomeEarlierSection: View {
    let entries: [TodayDigest.EarlierEntry]
    let onOpen: (Item) -> Void

    /// Every row reserves the width of the longest time, so "9:12 AM" and
    /// "10:40 AM" still start their titles on one line. The lead is set in
    /// mono, so the longest string is also the widest.
    private var timeSlot: String {
        entries
            .map { timeText(for: $0) }
            .max { $0.count < $1.count } ?? ""
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                TodaySectionHeader(title: "Earlier today")

                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    TodayRow(
                        lead: timeText(for: entry),
                        leadSlot: timeSlot,
                        title: entry.item.title,
                        note: entry.touch.label,
                        showsRule: index < entries.count - 1,
                        action: { onOpen(entry.item) }
                    )
                    .help("Open \(entry.item.title)")
                }
            }
            .padding(.top, Spacing.xl)
        }
    }

    private func timeText(for entry: TodayDigest.EarlierEntry) -> String {
        entry.touchedAt.formatted(date: .omitted, time: .shortened)
    }
}
