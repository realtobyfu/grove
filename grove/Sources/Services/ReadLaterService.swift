import Foundation
import SwiftData

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

/// Handles deferred inbox triage ("Read Later") by moving items into a queue
/// and returning them to inbox once their due date arrives.
@MainActor
@Observable
final class ReadLaterService {
    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func queue(_ item: Item, for preset: ReadLaterPreset) {
        queue(item, until: preset.scheduledDate())
    }

    func queue(_ item: Item, until date: Date) {
        guard date > .now else {
            item.status = .inbox
            item.readLaterUntil = nil
            item.updatedAt = .now
            try? modelContext.save()
            return
        }

        item.status = .queued
        item.readLaterUntil = date
        item.updatedAt = .now
        try? modelContext.save()
    }

    @discardableResult
    func restoreDueItems(referenceDate: Date = .now) -> Int {
        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        let queuedItems = allItems.filter { $0.status == .queued }
        var restoredCount = 0

        for item in queuedItems {
            let dueDate = item.readLaterUntil ?? .distantPast
            guard dueDate <= referenceDate else { continue }
            item.status = .inbox
            item.readLaterUntil = nil
            item.updatedAt = .now
            restoredCount += 1
        }

        if restoredCount > 0 {
            try? modelContext.save()
        }

        return restoredCount
    }
}
