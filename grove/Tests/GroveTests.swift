import Foundation
import Testing
@testable import grove

struct GroveTests {

    @Test func readLaterTomorrowMorningPresetSchedulesAtNineAM() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = makeDate(year: 2026, month: 2, day: 19, hour: 16, minute: 30, calendar: calendar)
        let scheduled = ReadLaterPreset.tomorrowMorning.scheduledDate(from: now, calendar: calendar)

        #expect(calendar.component(.year, from: scheduled) == 2026)
        #expect(calendar.component(.month, from: scheduled) == 2)
        #expect(calendar.component(.day, from: scheduled) == 20)
        #expect(calendar.component(.hour, from: scheduled) == 9)
        #expect(calendar.component(.minute, from: scheduled) == 0)
    }

    @Test func readLaterPresetOffsetsRespectConfiguredDayAndHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = makeDate(year: 2026, month: 2, day: 19, hour: 10, minute: 0, calendar: calendar)
        let tomorrowEvening = ReadLaterPreset.tomorrowEvening.scheduledDate(from: now, calendar: calendar)
        let threeDays = ReadLaterPreset.inThreeDays.scheduledDate(from: now, calendar: calendar)

        #expect(calendar.component(.day, from: tomorrowEvening) == 20)
        #expect(calendar.component(.hour, from: tomorrowEvening) == 18)
        #expect(calendar.component(.day, from: threeDays) == 22)
        #expect(calendar.component(.hour, from: threeDays) == 9)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = calendar.timeZone
        return calendar.date(from: components) ?? .now
    }

}
