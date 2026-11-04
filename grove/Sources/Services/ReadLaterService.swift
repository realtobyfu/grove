import Foundation
import SQLiteData

enum ReadLaterPreset: String, CaseIterable, Identifiable, Sendable {
    case tomorrowMorning
    case tomorrowEvening
    case inThreeDays

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tomorrowMorning:
            return "Tomorrow morning"
        case .tomorrowEvening:
            return "Tomorrow evening"
        case .inThreeDays:
            return "In 3 days"
        }
    }

    var hourOfDay: Int {
        switch self {
        case .tomorrowMorning, .inThreeDays:
            return 9
        case .tomorrowEvening:
            return 18
        }
    }

    var dayOffset: Int {
        switch self {
        case .tomorrowMorning, .tomorrowEvening:
            return 1
        case .inThreeDays:
            return 3
        }
    }

    func scheduledDate(from now: Date = .now, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) ?? startOfToday
        var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
        components.hour = hourOfDay
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? targetDay
    }
}

/// Protocol for read later service.
@MainActor
protocol ReadLaterServiceProtocol {
    func queue(_ itemID: Item.ID, for preset: ReadLaterPreset)
    func queue(_ itemID: Item.ID, until date: Date)
    func restore(_ itemID: Item.ID)
    @discardableResult func restoreDueItems(referenceDate: Date) -> Int
}

/// Handles deferred inbox triage ("Read Later") by moving items into a queue
/// and returning them to inbox once their due date arrives.
@MainActor
@Observable
final class ReadLaterService: ReadLaterServiceProtocol {
    private let database: any DatabaseWriter

    init(database: any DatabaseWriter = AppDatabase.current) {
        self.database = database
    }

    func queue(_ itemID: Item.ID, for preset: ReadLaterPreset) {
        queue(itemID, until: preset.scheduledDate())
    }

    func queue(_ itemID: Item.ID, until date: Date) {
        database.attempt { db in
            try Item.modify(itemID, in: db) { item in
                guard date > .now else {
                    item.status = .inbox
                    item.readLaterUntil = nil
                    item.updatedAt = .now
                    return
                }

                item.status = .queued
                item.readLaterUntil = date
                item.updatedAt = .now
            }
        }
    }

    /// Immediately returns a single queued item to the inbox. The one owner of
    /// the queued→inbox transition, so a future side effect (analytics, clearing
    /// a scheduled notification) lands everywhere.
    func restore(_ itemID: Item.ID) {
        database.attempt { db in
            try Item.modify(itemID, in: db) { item in
                item.status = .inbox
                item.readLaterUntil = nil
                item.updatedAt = .now
            }
        }
    }

    @discardableResult
    func restoreDueItems(referenceDate: Date = .now) -> Int {
        let restored = database.attempt { db -> Int in
            let allItems = try Item.all.fetchAll(db)
            let queuedItems = allItems.filter { $0.status == .queued }
            var restoredCount = 0

            for item in queuedItems {
                let dueDate = item.readLaterUntil ?? .distantPast
                guard dueDate <= referenceDate else { continue }
                try Item.modify(item.id, in: db) { item in
                    item.status = .inbox
                    item.readLaterUntil = nil
                    item.updatedAt = .now
                }
                restoredCount += 1
            }

            return restoredCount
        }

        return restored ?? 0
    }
}
