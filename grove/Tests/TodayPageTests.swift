import Foundation
import SwiftData
import Testing
@testable import grove

/// What the Today page lists beside the inbox: "Earlier today", the notes
/// under "Continue", and the words each row is given. All of it is worked
/// out by `TodayDigest` from an item's dates, type and status, with the clock
/// and calendar passed in.
@MainActor
struct TodayDigestTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// A moment in November 2026, in the test calendar. The 17th is a Tuesday.
    private func time(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func makeContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "TodayDigestTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @discardableResult
    private func insert(
        _ title: String,
        type: ItemType = .article,
        status: ItemStatus = .active,
        created: Date,
        updated: Date? = nil,
        in context: ModelContext
    ) -> Item {
        let item = Item(title: title, type: type)
        item.status = status
        item.createdAt = created
        item.updatedAt = updated ?? created
        context.insert(item)
        return item
    }

    private func earlier(_ items: [Item], now: Date, limit: Int = TodayDigest.earlierLimit) -> [TodayDigest.EarlierEntry] {
        TodayDigest.earlierToday(from: items, now: now, calendar: calendar, limit: limit)
    }

    // MARK: - Earlier today: what is listed

    @Test func onlyLibraryItemsTouchedTodayAreListed() throws {
        let context = try makeContext()
        let now = time(day: 17, hour: 15)
        let items = [
            insert("Kept this morning", created: time(day: 17, hour: 9, minute: 12), in: context),
            insert("Still in the inbox", status: .inbox, created: time(day: 17, hour: 10), in: context),
            insert("Dropped", status: .dismissed, created: time(day: 17, hour: 11), in: context),
            insert("Archived", status: .archived, created: time(day: 17, hour: 12), in: context),
            insert("Set aside for later", status: .queued, created: time(day: 17, hour: 13), in: context),
            insert("Kept yesterday", created: time(day: 16, hour: 9), in: context),
        ]

        #expect(earlier(items, now: now).map(\.item.title) == ["Kept this morning"])
    }

    @Test func nothingTouchedTodayIsAnEmptySection() throws {
        let context = try makeContext()
        let items = [insert("Last week", created: time(day: 10, hour: 9), in: context)]

        #expect(earlier(items, now: time(day: 17, hour: 15)).isEmpty)
        #expect(earlier([], now: time(day: 17, hour: 15)).isEmpty)
    }

    @Test func rowsRunNewestFirstByTheLaterOfCreatedAndUpdated() throws {
        let context = try makeContext()
        let now = time(day: 17, hour: 15)
        let items = [
            insert("Man-Computer Symbiosis", created: time(day: 12, hour: 8), updated: time(day: 17, hour: 8, minute: 55), in: context),
            insert(
                "Trails, not folders",
                type: .note,
                created: time(day: 17, hour: 8),
                updated: time(day: 17, hour: 10, minute: 40),
                in: context
            ),
            insert("The Bitter Lesson", created: time(day: 17, hour: 9, minute: 12), in: context),
        ]

        let entries = earlier(items, now: now)
        #expect(entries.map(\.item.title) == ["Trails, not folders", "The Bitter Lesson", "Man-Computer Symbiosis"])
        #expect(entries.map(\.touchedAt) == [
            time(day: 17, hour: 10, minute: 40),
            time(day: 17, hour: 9, minute: 12),
            time(day: 17, hour: 8, minute: 55),
        ])
    }

    @Test func theListStopsAtItsLimit() throws {
        let context = try makeContext()
        let now = time(day: 17, hour: 23)
        let items = (1...9).map { hour in
            insert("Item \(hour)", created: time(day: 17, hour: hour), in: context)
        }

        #expect(TodayDigest.earlierLimit == 6)
        #expect(earlier(items, now: now).map(\.item.title) == ["Item 9", "Item 8", "Item 7", "Item 6", "Item 5", "Item 4"])
        #expect(earlier(items, now: now, limit: 2).map(\.item.title) == ["Item 9", "Item 8"])
        #expect(earlier(items, now: now, limit: 0).isEmpty)
    }

    @Test func todayIsTheCalendarsDayNotTheLastTwentyFourHours() throws {
        let context = try makeContext()
        let lateLastNight = insert("Late last night", created: time(day: 16, hour: 23, minute: 59), in: context)
        let justAfterMidnight = insert("Just after midnight", created: time(day: 17, hour: 0, minute: 10), in: context)
        let items = [lateLastNight, justAfterMidnight]

        // Half past midnight UTC: only the second belongs to the 17th.
        let now = time(day: 17, hour: 0, minute: 30)
        #expect(earlier(items, now: now).map(\.item.title) == ["Just after midnight"])

        // In New York it is still the evening of the 16th, and both are today.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let entries = TodayDigest.earlierToday(from: items, now: now, calendar: newYork)
        #expect(entries.map(\.item.title) == ["Just after midnight", "Late last night"])
    }

    // MARK: - Earlier today: what a row says

    @Test func aNoteCreatedTodayWasWrittenAndAnOlderOneWasEdited() throws {
        let context = try makeContext()
        let now = time(day: 17, hour: 15)
        let written = insert("New", type: .note, created: time(day: 17, hour: 9), updated: time(day: 17, hour: 11), in: context)
        let edited = insert("Old", type: .note, created: time(day: 15, hour: 9), updated: time(day: 17, hour: 10), in: context)

        #expect(TodayDigest.touch(for: written, now: now, calendar: calendar) == .noteWritten)
        #expect(TodayDigest.touch(for: edited, now: now, calendar: calendar) == .noteEdited)
        #expect(earlier([written, edited], now: now).map(\.touch) == [.noteWritten, .noteEdited])
    }

    @Test func aSourceCapturedTodayWasSavedAndAnOlderOneWasUpdated() throws {
        let context = try makeContext()
        let now = time(day: 17, hour: 15)
        let saved = insert("New", type: .article, created: time(day: 17, hour: 9), updated: time(day: 17, hour: 11), in: context)
        let updated = insert("Old", type: .video, created: time(day: 3, hour: 9), updated: time(day: 17, hour: 10), in: context)

        #expect(TodayDigest.touch(for: saved, now: now, calendar: calendar) == .saved)
        #expect(TodayDigest.touch(for: updated, now: now, calendar: calendar) == .updated)
    }

    @Test func labelsSayOnlyWhatTheModelKnows() {
        #expect(TodayDigest.Touch.noteWritten.label == "Note written")
        #expect(TodayDigest.Touch.noteEdited.label == "Note edited")
        #expect(TodayDigest.Touch.saved.label == "Saved")
        #expect(TodayDigest.Touch.updated.label == "Updated")
    }

    // MARK: - Continue

    @Test func continueIsTheMostRecentlyEditedKeptNotes() throws {
        let context = try makeContext()
        let items = [
            insert("Oldest note", type: .note, created: time(day: 1, hour: 9), in: context),
            insert("Sunday's note", type: .note, created: time(day: 2, hour: 9), updated: time(day: 15, hour: 9), in: context),
            insert("Today's note", type: .note, created: time(day: 17, hour: 9), in: context),
            insert("Monday's note", type: .note, created: time(day: 16, hour: 9), in: context),
            // Not notes in progress: a note still in the inbox, one archived,
            // and a source, however recently each was touched.
            insert("Captured thought", type: .note, status: .inbox, created: time(day: 17, hour: 12), in: context),
            insert("Archived note", type: .note, status: .archived, created: time(day: 17, hour: 13), in: context),
            insert("An article", type: .article, created: time(day: 17, hour: 14), in: context),
        ]

        #expect(TodayDigest.continueLimit == 3)
        #expect(TodayDigest.continueNotes(from: items).map(\.title) == ["Today's note", "Monday's note", "Sunday's note"])
        #expect(TodayDigest.continueNotes(from: items, limit: 1).map(\.title) == ["Today's note"])
    }

    @Test func continueIsEmptyWithoutKeptNotes() throws {
        let context = try makeContext()
        let items = [insert("An article", created: time(day: 17, hour: 9), in: context)]

        #expect(TodayDigest.continueNotes(from: items).isEmpty)
        #expect(TodayDigest.continueNotes(from: []).isEmpty)
    }

    // MARK: - Snippet

    @Test func theSnippetIsTheFirstLineThatSaysSomething() {
        #expect(TodayDigest.snippet(from: "A board should read like a route.\nSecond line.") == "A board should read like a route.")
        #expect(TodayDigest.snippet(from: "\n\n   \nAfter blank lines") == "After blank lines")
    }

    @Test func markdownMarksAreTakenOffTheSnippet() {
        #expect(TodayDigest.snippet(from: "# Trails, not folders\n\nBody.") == "Trails, not folders")
        #expect(TodayDigest.snippet(from: "- [ ] **Read** the _memex_ essay") == "Read the memex essay")
        #expect(TodayDigest.snippet(from: "1. First point") == "First point")
        #expect(TodayDigest.snippet(from: "> quoted line") == "quoted line")
        #expect(TodayDigest.snippet(from: "~~struck~~ and `code`") == "struck and code")
        #expect(
            TodayDigest.snippet(from: "See [[As We May Think]] and [the demo](https://example.com).")
                == "See As We May Think and the demo."
        )
    }

    @Test func underscoresInsideAWordAreNotEmphasis() {
        #expect(TodayDigest.snippet(from: "use snake_case here") == "use snake_case here")
    }

    @Test func dividersAndCodeFencesAreSkipped() {
        #expect(TodayDigest.snippet(from: "---\n```swift\nlet x = 1\n```") == "let x = 1")
    }

    @Test func aNoteWithNoWordsHasNoSnippet() {
        #expect(TodayDigest.snippet(from: nil) == nil)
        #expect(TodayDigest.snippet(from: "") == nil)
        #expect(TodayDigest.snippet(from: "   \n\t\n") == nil)
        #expect(TodayDigest.snippet(from: "***") == nil)
    }

    @Test func aLongLineIsCutWithAnEllipsis() throws {
        let long = String(repeating: "word ", count: 60)
        let snippet = try #require(TodayDigest.snippet(from: long))

        #expect(snippet.hasSuffix("\u{2026}"))
        #expect(snippet.count <= TodayDigest.snippetLimit + 1)
        #expect(long.hasPrefix(String(snippet.dropLast())))

        // A line at the limit is left whole.
        let exact = String(repeating: "a", count: TodayDigest.snippetLimit)
        #expect(TodayDigest.snippet(from: exact) == exact)
    }

    // MARK: - Word count

    @Test func wordsAreRunsBetweenWhitespace() {
        #expect(TodayDigest.wordCount(of: "one two\nthree") == 3)
        #expect(TodayDigest.wordCount(of: "  spaced   out  ") == 2)
        #expect(TodayDigest.wordCount(of: "") == 0)
        #expect(TodayDigest.wordCount(of: nil) == 0)
    }

    @Test func theWordCountLabelAgreesInNumberAndIsLeftOffAnEmptyNote() {
        #expect(TodayDigest.wordCountLabel(for: "one two three") == "3 words")
        #expect(TodayDigest.wordCountLabel(for: "one") == "1 word")
        #expect(TodayDigest.wordCountLabel(for: "   ") == nil)
        #expect(TodayDigest.wordCountLabel(for: nil) == nil)
    }

    // MARK: - Masthead

    @Test func theMastheadNamesTheWeekdayTheDayAndTheMonth() {
        let title = TodayDigest.mastheadTitle(
            for: time(day: 17, hour: 12),
            locale: Locale(identifier: "en_GB"),
            calendar: calendar
        )

        #expect(title.contains("Tuesday"))
        #expect(title.contains("17"))
        #expect(title.contains("November"))
        // The year is not part of a day's title.
        #expect(!title.contains("2026"))
    }

    @Test func theMastheadUsesTheCalendarsDay() {
        // 02:00 UTC on the 18th is still the evening of the 17th in New York.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let title = TodayDigest.mastheadTitle(
            for: time(day: 18, hour: 2),
            locale: Locale(identifier: "en_GB"),
            calendar: newYork
        )

        #expect(title.contains("Tuesday"))
        #expect(title.contains("17"))
    }
}

/// Where the inbox's focus sits as the list changes around it, and what the
/// one-line rows under the focused item say.
@MainActor
struct InboxFocusTests {
    private let first = UUID()
    private let second = UUID()
    private let third = UUID()

    @Test func focusFollowsTheItemWhenTheListChangesAroundIt() {
        // A capture arrives on top: the focused item moves down a place.
        let arrival = UUID()
        #expect(InboxFocus.index(following: second, previousIndex: 1, in: [arrival, first, second, third]) == 2)
        // An item above it leaves: it moves up a place.
        #expect(InboxFocus.index(following: second, previousIndex: 1, in: [second, third]) == 0)
    }

    @Test func whenTheFocusedItemLeavesTheNextOneTakesItsPlace() {
        #expect(InboxFocus.index(following: second, previousIndex: 1, in: [first, third]) == 1)
        // The last row left: focus falls back to the new last row.
        #expect(InboxFocus.index(following: third, previousIndex: 2, in: [first, second]) == 1)
    }

    @Test func withNothingRememberedFocusStaysWhereItWas() {
        #expect(InboxFocus.index(following: nil, previousIndex: 0, in: [first, second]) == 0)
        #expect(InboxFocus.index(following: nil, previousIndex: 1, in: [first, second]) == 1)
        #expect(InboxFocus.index(following: nil, previousIndex: 7, in: [first, second]) == 1)
    }

    @Test func anEmptyInboxFocusesNothing() {
        #expect(InboxFocus.index(following: first, previousIndex: 3, in: []) == 0)
        #expect(InboxFocus.clampedIndex(3, count: 0) == 0)
    }

    @Test func anIndexIsAlwaysClampedIntoTheList() {
        #expect(InboxFocus.clampedIndex(-1, count: 3) == 0)
        #expect(InboxFocus.clampedIndex(1, count: 3) == 1)
        #expect(InboxFocus.clampedIndex(3, count: 3) == 2)
    }

    @Test func theLastRowIsTheLastItemThatIsNotInFocus() {
        #expect(InboxFocus.lastRowIndex(count: 3, focused: 0) == 2)
        #expect(InboxFocus.lastRowIndex(count: 3, focused: 1) == 2)
        #expect(InboxFocus.lastRowIndex(count: 3, focused: 2) == 1)
        // One item is the focused card and nothing else.
        #expect(InboxFocus.lastRowIndex(count: 1, focused: 0) == nil)
        #expect(InboxFocus.lastRowIndex(count: 0, focused: 0) == nil)
    }

    @Test func aRowNamesItsSourceOrItsKind() throws {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "InboxFocusTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))

        let article = Item(title: "As We May Think", type: .article)
        article.sourceURL = "https://www.theatlantic.com/magazine/archive/1945/07/as-we-may-think/303881/"
        context.insert(article)
        #expect(InboxFocus.sourceLabel(for: article) == "theatlantic.com")

        let thought = Item(title: "A thought", type: .note)
        context.insert(thought)
        #expect(InboxFocus.sourceLabel(for: thought) == "Note")

        let blank = Item(title: "No source", type: .video)
        blank.sourceURL = "   "
        context.insert(blank)
        #expect(InboxFocus.sourceLabel(for: blank) == "Video")
    }
}

/// The widths at which Today rearranges: two columns when there is room for
/// both, one when the right page is open or the window is small.
struct TodayLayoutTests {
    private let threshold = TodayLayout.minArrivedWidth + TodayLayout.yoursColumnWidth

    @Test func twoColumnsNeedRoomForBoth() {
        #expect(TodayLayout.usesTwoColumns(pageWidth: threshold))
        #expect(TodayLayout.usesTwoColumns(pageWidth: threshold + 200))
        #expect(!TodayLayout.usesTwoColumns(pageWidth: threshold - 1))
        #expect(!TodayLayout.usesTwoColumns(pageWidth: 0))
    }

    @Test func theDefaultWindowIsTwoColumnsAndTheRightPageMakesItOne() {
        // 1200pt window, 248pt sidebar.
        let page: CGFloat = 1200 - 248
        #expect(TodayLayout.usesTwoColumns(pageWidth: page))
        // The same window with the right page open at its standard 360pt.
        #expect(!TodayLayout.usesTwoColumns(pageWidth: page - 360))
    }

    @Test func arrivedGivesUpTheYoursColumnOnlyWhenItIsBeside() {
        let gutter: CGFloat = 28
        // Two columns: the page less the Yours column, less both gutters.
        #expect(TodayLayout.arrivedContentWidth(pageWidth: 952, gutter: gutter) == 952 - TodayLayout.yoursColumnWidth - 2 * gutter)
        // One column: the whole page, less both gutters.
        #expect(TodayLayout.arrivedContentWidth(pageWidth: 600, gutter: gutter) == 600 - 2 * gutter)
    }

    @Test func arrivedNeverRunsWiderThanItsMeasureOrNarrowerThanNothing() {
        #expect(TodayLayout.arrivedContentWidth(pageWidth: 4000, gutter: 28) == TodayLayout.arrivedMeasure)
        #expect(TodayLayout.arrivedContentWidth(pageWidth: 20, gutter: 28) == 0)
    }

    @Test func theCoverSitsBesideTheTextOnlyInAWideColumn() {
        #expect(TodayLayout.coverSitsBeside(contentWidth: TodayLayout.coverBesideMinWidth))
        #expect(!TodayLayout.coverSitsBeside(contentWidth: TodayLayout.coverBesideMinWidth - 1))

        // The default window sets it beside. A page only just wide enough
        // for two columns, and a one-column page squeezed to the least the
        // right page leaves it (360pt), both set it above.
        let roomy = TodayLayout.arrivedContentWidth(pageWidth: 952, gutter: 28)
        let justTwoColumns = TodayLayout.arrivedContentWidth(pageWidth: threshold, gutter: 28)
        let squeezed = TodayLayout.arrivedContentWidth(pageWidth: 360, gutter: 28)
        #expect(TodayLayout.coverSitsBeside(contentWidth: roomy))
        #expect(!TodayLayout.coverSitsBeside(contentWidth: justTwoColumns))
        #expect(!TodayLayout.coverSitsBeside(contentWidth: squeezed))
    }
}
