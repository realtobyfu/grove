import SwiftUI

struct WeekSection: Identifiable {
    let id: String
    let title: String
    let items: [Item]

    static func group(_ items: [Item]) -> [WeekSection] {
        let calendar = Calendar.current
        let now = Date()

        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
        let lastWeekStart = thisWeekStart.flatMap { calendar.date(byAdding: .weekOfYear, value: -1, to: $0) }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        var buckets: [Date: [Item]] = [:]

        for item in items {
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: item.createdAt) else { continue }
            buckets[weekInterval.start, default: []].append(item)
        }

        return buckets
            .sorted { $0.key > $1.key }
            .map { weekStart, weekItems in
                let title: String
                if weekStart == thisWeekStart {
                    title = "This Week"
                } else if weekStart == lastWeekStart {
                    title = "Last Week"
                } else {
                    title = "Week of \(formatter.string(from: weekStart))"
                }

                let sorted = weekItems.sorted { $0.createdAt > $1.createdAt }
                return WeekSection(
                    id: weekStart.timeIntervalSince1970.description,
                    title: title,
                    items: sorted
                )
            }
    }
}

struct WeekSectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .sectionHeaderStyle()
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
