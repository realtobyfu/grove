import Foundation
import Testing
@testable import grove

/// The Library as an index: month headings, the date and board a row carries,
/// the word that names an item's type, and what an empty list says.
struct LibraryIndexTests {
    private let locale = Locale(identifier: "en_US")

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        try #require(utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func sections(_ dates: [Date], calendar: Calendar? = nil) -> [LibraryMonthSection<Date>] {
        LibraryIndex.monthSections(dates, calendar: calendar ?? utc, locale: locale) { $0 }
    }

    // MARK: - Month sections

    @Test func rowsAreGroupedUnderTheMonthAndYearOfTheirDate() throws {
        let dates = try [
            day(2026, 11, 17),
            day(2026, 11, 2),
            day(2026, 10, 30),
            day(2025, 11, 5),
        ]

        let result = sections(dates)

        #expect(result.map(\.id) == ["2026-11", "2026-10", "2025-11"])
        #expect(result.map(\.title) == ["November 2026", "October 2026", "November 2025"])
        #expect(result.map(\.elements) == [[dates[0], dates[1]], [dates[2]], [dates[3]]])
    }

    @Test func inputOrderIsKeptAndAMonthMetAgainJoinsItsSection() throws {
        let midNovember = try day(2026, 11, 17)
        let october = try day(2026, 10, 30)
        let earlyNovember = try day(2026, 11, 2)

        let result = sections([midNovember, october, earlyNovember])

        #expect(result.map(\.id) == ["2026-11", "2026-10"])
        #expect(result.first?.elements == [midNovember, earlyNovember])
    }

    @Test func oldestFirstInputGivesOldestFirstSections() throws {
        let dates = try [day(2026, 1, 9), day(2026, 2, 1), day(2026, 12, 31)]

        let result = sections(dates)

        #expect(result.map(\.id) == ["2026-01", "2026-02", "2026-12"])
        #expect(result.map(\.title) == ["January 2026", "February 2026", "December 2026"])
    }

    @Test func theMonthIsReadInTheCalendarsTimeZone() throws {
        // 02:00 UTC on 1 November is still the evening of 31 October in Los Angeles.
        let instant = try day(2026, 11, 1, hour: 2)
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        #expect(sections([instant]).map(\.title) == ["November 2026"])
        #expect(sections([instant], calendar: pacific).map(\.id) == ["2026-10"])
        #expect(sections([instant], calendar: pacific).map(\.title) == ["October 2026"])
    }

    @Test func nothingToGroupGivesNoSections() {
        #expect(sections([]).isEmpty)
    }

    @Test func elementsOfAnyTypeAreGroupedByTheDateTheClosureGives() throws {
        struct Entry: Equatable {
            let name: String
            let date: Date
        }
        let entries = try [
            Entry(name: "b", date: day(2026, 11, 3)),
            Entry(name: "a", date: day(2026, 11, 1)),
            Entry(name: "c", date: day(2026, 9, 1)),
        ]

        let result = LibraryIndex.monthSections(entries, calendar: utc, locale: locale) { $0.date }

        #expect(result.map { $0.elements.map(\.name) } == [["b", "a"], ["c"]])
    }

    // MARK: - Row date

    @Test func underAMonthHeadingARowShowsDayAndMonth() throws {
        let now = try day(2026, 11, 17)

        let thisYear = try LibraryIndex.dateLabel(
            for: day(2026, 11, 11), carriesYear: false, now: now, calendar: utc, locale: locale
        )
        let anotherYear = try LibraryIndex.dateLabel(
            for: day(2024, 11, 11), carriesYear: false, now: now, calendar: utc, locale: locale
        )

        #expect(thisYear == "Nov 11")
        #expect(anotherYear == "Nov 11")
    }

    @Test func withNoHeadingADateFromAnotherYearShowsItsYear() throws {
        let now = try day(2026, 11, 17)

        let thisYear = try LibraryIndex.dateLabel(
            for: day(2026, 3, 9), carriesYear: true, now: now, calendar: utc, locale: locale
        )
        let anotherYear = try LibraryIndex.dateLabel(
            for: day(2024, 11, 11), carriesYear: true, now: now, calendar: utc, locale: locale
        )

        #expect(thisYear == "Mar 9")
        #expect(anotherYear == "Nov 2024")
    }

    // MARK: - Board and type labels

    @Test func anItemWithNoBoardIsUnfiled() {
        #expect(LibraryIndex.boardLabel(nil) == "Unfiled")
        #expect(LibraryIndex.boardLabel("") == "Unfiled")
        #expect(LibraryIndex.boardLabel("Typography") == "Typography")
    }

    @Test func aLongBoardNameIsCutToTheLimitAndMarked() {
        #expect(LibraryIndex.boardLabel("abcdefghij", limit: 5) == "abcd\u{2026}")
        #expect(LibraryIndex.boardLabel("abcde", limit: 5) == "abcde")
        // The cut does not leave a space before the ellipsis.
        #expect(LibraryIndex.boardLabel("ab cdefgh", limit: 4) == "ab\u{2026}")
    }

    @Test func everyTypeHasAOneWordLabel() {
        #expect(ItemType.article.indexLabel == "Article")
        #expect(ItemType.note.indexLabel == "Note")
        #expect(ItemType.video.indexLabel == "Video")
        #expect(ItemType.codebase.indexLabel == "Code")
        #expect(ItemType.courseLecture.indexLabel == "Lecture")
    }

    // MARK: - Sort options

    @Test func theDateSortsGroupByMonthAndTitleOrderDoesNot() {
        #expect(LibrarySortOption.recentlyUpdated.groupsByMonth)
        #expect(LibrarySortOption.dateAdded.groupsByMonth)
        #expect(!LibrarySortOption.titleAZ.groupsByMonth)
    }

    // MARK: - Empty states

    private func empty(
        query: String = "",
        searching: Bool = false,
        board: String? = nil,
        archived: Bool = false
    ) -> LibraryEmptyState {
        LibraryEmptyState.resolve(
            query: query,
            isSearching: searching,
            boardTitle: board,
            showingArchived: archived
        )
    }

    @Test func anEmptyLibrarySaysNothingIsSavedYet() {
        #expect(empty() == .message(
            title: "Nothing saved yet.",
            detail: "Capture items to start building your knowledge base."
        ))
    }

    @Test func anEmptyFilterSaysWhichFilterIsEmpty() {
        #expect(empty(board: "Typography") == .message(
            title: "Nothing on this board yet.",
            detail: "Items you file under it are listed here."
        ))
        #expect(empty(archived: true) == .message(
            title: "Nothing archived.",
            detail: "Items you archive are kept here."
        ))
        #expect(empty(board: "Typography", archived: true) == .message(
            title: "Nothing archived.",
            detail: "No archived items on this board."
        ))
    }

    @Test func aQueryWithNoResultsNamesTheQuery() {
        #expect(empty(query: "  memex ") == .message(
            title: "Nothing matches \u{201C}memex\u{201D}.",
            detail: "Try a shorter word or a different spelling."
        ))
        #expect(empty(query: "memex", board: "Typography") == .message(
            title: "Nothing matches \u{201C}memex\u{201D}.",
            detail: "Try different words, or clear the filter."
        ))
    }

    @Test func aQueryStillBeingSearchedIsNotCalledEmpty() {
        #expect(empty(query: "memex", searching: true) == .searching)
        // No query: there is nothing to wait for.
        #expect(empty(query: "   ", searching: true) != .searching)
    }
}
