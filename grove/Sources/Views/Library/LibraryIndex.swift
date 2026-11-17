import Foundation

// The Library as an index: the pure rules behind the list with no query in
// the find field. Month headings, the date a row carries, and the short word
// that names an item's type. Nothing here touches SwiftUI or SwiftData, so it
// is covered directly by LibraryIndexTests.

// MARK: - Month Sections

/// One month's run of rows in the Library index.
struct LibraryMonthSection<Element>: Identifiable {
    /// Year and month in the grouping calendar, e.g. "2026-11".
    let id: String
    /// The heading, e.g. "November 2026".
    let title: String
    let elements: [Element]
}

enum LibraryIndex {
    /// Groups `elements` under month headings by the date `date` gives each.
    ///
    /// The order of the input is kept: sections appear in the order their
    /// month is first met, and rows keep their order inside a section. The
    /// caller sorts (newest first for the two date sorts); a month met again
    /// later joins its existing section, so a heading never repeats.
    static func monthSections<Element>(
        _ elements: [Element],
        calendar: Calendar = .current,
        locale: Locale = .current,
        date: (Element) -> Date
    ) -> [LibraryMonthSection<Element>] {
        var order: [String] = []
        var monthStarts: [String: Date] = [:]
        var buckets: [String: [Element]] = [:]

        for element in elements {
            let day = date(element)
            let parts = calendar.dateComponents([.year, .month], from: day)
            let year = parts.year ?? 0
            let month = parts.month ?? 0
            let key = "\(year)-\(month < 10 ? "0" : "")\(month)"

            if buckets[key] == nil {
                order.append(key)
                monthStarts[key] = calendar.date(from: DateComponents(year: year, month: month)) ?? day
            }
            buckets[key, default: []].append(element)
        }

        return order.map { key in
            LibraryMonthSection(
                id: key,
                title: monthTitle(for: monthStarts[key] ?? .distantPast, calendar: calendar, locale: locale),
                elements: buckets[key] ?? []
            )
        }
    }

    /// "November 2026": the heading over a month of rows.
    static func monthTitle(
        for date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        date.formatted(style(calendar: calendar, locale: locale).month(.wide).year())
    }

    // MARK: - Row Date

    /// The date at the right of a row.
    ///
    /// Under a month heading the year is already on the page, so a row shows
    /// the day and month ("Nov 11"). Where there is no heading (Title A–Z,
    /// find results) `carriesYear` is true, and a date from another year
    /// gives up its day for the year ("Nov 2024") so that it cannot be read
    /// as this year's.
    static func dateLabel(
        for date: Date,
        carriesYear: Bool,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let base = style(calendar: calendar, locale: locale)
        if carriesYear, !calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(base.month(.abbreviated).year())
        }
        return date.formatted(base.day().month(.abbreviated))
    }

    private static func style(calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    // MARK: - Type Label

    /// The word set in the type column for a reflection found by the find
    /// field. Abbreviated to sit in the same column as the item types.
    static let reflectionLabel = "Reflect."
}

// MARK: - Item Type Label

extension ItemType {
    /// The type as one short word for the type column of an index row.
    /// `displayName` where that is already one word; shortened where it is not.
    var indexLabel: String {
        switch self {
        case .codebase: "Code"
        case .courseLecture: "Lecture"
        default: displayName
        }
    }
}
