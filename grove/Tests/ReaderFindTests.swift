import Foundation
import SwiftData
import Testing
@testable import grove

/// Find-in-article: where ⌘F goes, what the bar says, how matches are counted
/// and stepped through (`ReaderFind`), and the page scripts that support
/// WebKit's own find — run in JavaScriptCore against a stand-in DOM to show
/// they read the page and move its selection, and never change the document.
struct ReaderFindTests {

    // MARK: - ⌘F routing

    private func target(reader: Bool, canFind: Bool, overlay: Bool) -> ReaderFind.ShortcutTarget {
        ReaderFind.shortcutTarget(readerIsOpen: reader, surfaceCanFind: canFind, overlayIsUp: overlay)
    }

    @Test func findGoesToTheArticleOnlyOnAReadingSurfaceWithNothingOverIt() {
        #expect(target(reader: true, canFind: true, overlay: false) == .article)
    }

    @Test func everyOtherStateIsLibrarySearch() {
        // The search or capture overlay is already up over the reader.
        #expect(target(reader: true, canFind: true, overlay: true) == .library)
        // The item overview: native text, with no find of its own.
        #expect(target(reader: true, canFind: false, overlay: false) == .library)
        #expect(target(reader: true, canFind: false, overlay: true) == .library)
        // A surface flag left over with no reader open must not capture ⌘F.
        #expect(target(reader: false, canFind: true, overlay: false) == .library)
        #expect(target(reader: false, canFind: true, overlay: true) == .library)
        #expect(target(reader: false, canFind: false, overlay: false) == .library)
        #expect(target(reader: false, canFind: false, overlay: true) == .library)
    }

    // MARK: - Status label

    @Test func labelCountsMatchesWithTheRightNoun() {
        #expect(ReaderFind.label(for: .matches(count: 12, current: nil)) == "12 matches")
        #expect(ReaderFind.label(for: .matches(count: 1, current: nil)) == "1 match")
        #expect(ReaderFind.label(for: .matches(count: 2, current: nil)) == "2 matches")
    }

    @Test func labelShowsAPositionOnlyWhenTheSurfaceGaveOne() {
        #expect(ReaderFind.label(for: .matches(count: 12, current: 3)) == "3 of 12")
        #expect(ReaderFind.label(for: .matches(count: 1, current: 1)) == "1 of 1")
    }

    @Test func labelIgnoresAPositionOutsideTheCount() {
        #expect(ReaderFind.label(for: .matches(count: 12, current: 0)) == "12 matches")
        #expect(ReaderFind.label(for: .matches(count: 12, current: 13)) == "12 matches")
        #expect(ReaderFind.label(for: .matches(count: 12, current: -1)) == "12 matches")
    }

    @Test func labelForNothingFoundAndNothingAsked() {
        #expect(ReaderFind.label(for: .noMatches) == "No matches")
        #expect(ReaderFind.label(for: .matches(count: 0, current: nil)) == "No matches")
        #expect(ReaderFind.label(for: .idle) == "")
        #expect(ReaderFind.label(for: .found) == "Found")
    }

    // MARK: - Web status

    @Test func webStatusNeverContradictsWebKit() {
        // WebKit found nothing: no count over the page text can overrule it.
        #expect(ReaderFind.webStatus(matchFound: false, counted: 7) == .noMatches)
        #expect(ReaderFind.webStatus(matchFound: false, counted: nil) == .noMatches)
        // WebKit found a match the count missed: say so without a number.
        #expect(ReaderFind.webStatus(matchFound: true, counted: 0) == .found)
        #expect(ReaderFind.webStatus(matchFound: true, counted: nil) == .found)
    }

    @Test func webStatusCarriesACountButNeverAPosition() {
        #expect(ReaderFind.webStatus(matchFound: true, counted: 12) == .matches(count: 12, current: nil))
        #expect(ReaderFind.webStatus(matchFound: true, counted: 1) == .matches(count: 1, current: nil))
    }

    // MARK: - Stepping

    @Test func steppingWrapsAtBothEnds() {
        #expect(ReaderFind.steppedIndex(from: 0, count: 3, forward: true) == 1)
        #expect(ReaderFind.steppedIndex(from: 2, count: 3, forward: true) == 0)
        #expect(ReaderFind.steppedIndex(from: 2, count: 3, forward: false) == 1)
        #expect(ReaderFind.steppedIndex(from: 0, count: 3, forward: false) == 2)
    }

    @Test func steppingASingleMatchStaysOnIt() {
        #expect(ReaderFind.steppedIndex(from: 0, count: 1, forward: true) == 0)
        #expect(ReaderFind.steppedIndex(from: 0, count: 1, forward: false) == 0)
    }

    @Test func steppingWithNoCurrentMatchStartsAtAnEnd() {
        #expect(ReaderFind.steppedIndex(from: nil, count: 4, forward: true) == 0)
        #expect(ReaderFind.steppedIndex(from: nil, count: 4, forward: false) == 3)
        // A stale index from a longer list is treated the same way.
        #expect(ReaderFind.steppedIndex(from: 9, count: 4, forward: true) == 0)
        #expect(ReaderFind.steppedIndex(from: -1, count: 4, forward: false) == 3)
    }

    @Test func steppingThroughNothingGoesNowhere() {
        #expect(ReaderFind.steppedIndex(from: nil, count: 0, forward: true) == nil)
        #expect(ReaderFind.steppedIndex(from: 0, count: 0, forward: false) == nil)
    }

    // MARK: - Counting

    @Test func countIgnoresCase() {
        let text = "Moss grows. MOSS spreads. The moss is patient."
        #expect(ReaderFind.occurrenceCount(of: "moss", in: text) == 3)
        #expect(ReaderFind.occurrenceCount(of: "MoSs", in: text) == 3)
    }

    @Test func countFindsMatchesInsideWords() {
        #expect(ReaderFind.occurrenceCount(of: "art", in: "The article is part of the chart.") == 3)
    }

    @Test func countDoesNotOverlap() {
        #expect(ReaderFind.occurrenceCount(of: "aa", in: "aaaa") == 2)
        #expect(ReaderFind.occurrenceCount(of: "aa", in: "aaaaa") == 2)
        #expect(ReaderFind.occurrenceCount(of: "ana", in: "banana") == 1)
    }

    @Test func countOfNothingOrInNothingIsZero() {
        #expect(ReaderFind.occurrenceCount(of: "", in: "anything at all") == 0)
        #expect(ReaderFind.occurrenceCount(of: "moss", in: "") == 0)
        #expect(ReaderFind.occurrenceCount(of: "moss", in: "lichen and fern") == 0)
    }

    @Test func countMatchesAtBothEndsAndTheWholeText() {
        #expect(ReaderFind.occurrenceCount(of: "moss", in: "moss and more moss") == 2)
        #expect(ReaderFind.occurrenceCount(of: "moss", in: "moss") == 1)
        #expect(ReaderFind.occurrenceCount(of: "mosses", in: "moss") == 0)
    }

    @Test func countKeepsSpacesInTheQuerySignificant() {
        let text = "the cat\nthe cat sat"
        #expect(ReaderFind.occurrenceCount(of: "the cat", in: text) == 2)
        #expect(ReaderFind.occurrenceCount(of: "cat ", in: text) == 1)
        // A space does not reach across a line break.
        #expect(ReaderFind.occurrenceCount(of: "cat the", in: text) == 0)
    }

    @Test func countTreatsTypographicAndStraightQuotesAlike() {
        let text = "It\u{2019}s the reader\u{2019}s \u{201C}own\u{201D} copy."
        #expect(ReaderFind.occurrenceCount(of: "it's", in: text) == 1)
        #expect(ReaderFind.occurrenceCount(of: "\"own\"", in: text) == 1)
        // And the other way round: curly typed, straight on the page.
        #expect(ReaderFind.occurrenceCount(of: "it\u{2019}s", in: "It's here") == 1)
    }

    @Test func countTreatsNoBreakSpaceAsSpaceAndDropsSoftHyphens() {
        #expect(ReaderFind.occurrenceCount(of: "10 km", in: "about 10\u{00A0}km away") == 1)
        #expect(ReaderFind.occurrenceCount(of: "photosynthesis", in: "photo\u{00AD}syn\u{00AD}thesis") == 1)
    }

    @Test func plainQueryMatchesAccentedTextButAnAccentedQueryAsksForAccents() {
        let text = "A résumé is not a resume."
        #expect(ReaderFind.occurrenceCount(of: "resume", in: text) == 2)
        #expect(ReaderFind.occurrenceCount(of: "résumé", in: text) == 1)
    }

    @Test func countOverPrefoldedTextMatchesTheOneCallForm() {
        let text = "\u{201C}Moss\u{201D} and moss and MOSS\u{00A0}again"
        let folded = ReaderFind.searchFolded(text)
        for query in ["moss", "\"moss\"", "moss again", "fern"] {
            #expect(
                ReaderFind.occurrenceCount(of: query, inFolded: folded)
                    == ReaderFind.occurrenceCount(of: query, in: text),
                "\(query)"
            )
        }
    }

    @Test func foldingLeavesOrdinaryTextAlone() {
        let text = "Plain text, with CASE and accénts kept."
        #expect(ReaderFind.searchFolded(text) == text)
    }

    // MARK: - Whose selection is it

    @Test func aSelectionEqualToTheQueryIsFinds() {
        #expect(ReaderFind.isFindSelection("moss", query: "moss"))
        #expect(ReaderFind.isFindSelection("Moss", query: "moss"))
        #expect(ReaderFind.isFindSelection("  moss\n", query: "moss"))
        #expect(ReaderFind.isFindSelection("résumé", query: "resume"))
        #expect(ReaderFind.isFindSelection("reader\u{2019}s", query: "reader's"))
        #expect(ReaderFind.isFindSelection("the\n   cat", query: "the cat"))
    }

    @Test func anyOtherSelectionIsTheReaders() {
        #expect(!ReaderFind.isFindSelection("moss grows slowly", query: "moss"))
        #expect(!ReaderFind.isFindSelection("mos", query: "moss"))
        #expect(!ReaderFind.isFindSelection("fern", query: "moss"))
    }

    @Test func noSelectionOrNoQueryIsNeverFinds() {
        #expect(!ReaderFind.isFindSelection(nil, query: "moss"))
        #expect(!ReaderFind.isFindSelection("", query: "moss"))
        #expect(!ReaderFind.isFindSelection("moss", query: ""))
        #expect(!ReaderFind.isFindSelection("", query: ""))
        #expect(!ReaderFind.isFindSelection("   ", query: "   "))
    }

    // MARK: - Page scripts

    private let article = #"<p>The <em>quick</em> brown fox.</p><p>A second fox, quick as ever.</p>"#

    @Test func pageTextScriptReturnsTheDocumentText() throws {
        let harness = try ReaderJSHarness(body: article)
        let text = try harness.run(ReaderFind.pageTextJS).toString() ?? ""
        #expect(ReaderFind.occurrenceCount(of: "quick", in: text) == 2)
        #expect(ReaderFind.occurrenceCount(of: "FOX", in: text) == 2)
        #expect(ReaderFind.occurrenceCount(of: "moss", in: text) == 0)
    }

    @Test func selectionTextScriptReportsTheSelectionOrNothing() throws {
        let harness = try ReaderJSHarness(body: article)
        #expect(try harness.run(ReaderFind.selectionTextJS).toString() == "")
        try harness.setSelection("quick")
        #expect(try harness.run(ReaderFind.selectionTextJS).toString() == "quick")
    }

    /// A stand-in selection that counts what is asked of it.
    private func installCountingSelection(in harness: ReaderJSHarness, collapsed: Bool) throws {
        try harness.run("""
        window.__selection = {
            rangeCount: 1,
            isCollapsed: \(collapsed),
            collapses: 0,
            removals: 0,
            toString: function() { return 'quick'; },
            collapseToStart: function() { this.collapses++; this.isCollapsed = true; },
            removeAllRanges: function() { this.removals++; this.rangeCount = 0; }
        };
        """)
    }

    @Test func anchorScriptCollapsesAnOpenSelectionOnce() throws {
        let harness = try ReaderJSHarness(body: article)
        try installCountingSelection(in: harness, collapsed: false)
        try harness.run(ReaderFind.anchorSelectionJS)
        #expect(try harness.run("window.__selection.collapses").toInt32() == 1)
        // Already a caret: nothing left to collapse.
        try harness.run(ReaderFind.anchorSelectionJS)
        #expect(try harness.run("window.__selection.collapses").toInt32() == 1)
    }

    @Test func anchorScriptToleratesAPageWithNoSelection() throws {
        let harness = try ReaderJSHarness(body: article)
        #expect(try harness.run(ReaderFind.anchorSelectionJS).toBool())
    }

    @Test func clearScriptDropsTheSelection() throws {
        let harness = try ReaderJSHarness(body: article)
        try installCountingSelection(in: harness, collapsed: false)
        try harness.run(ReaderFind.clearSelectionJS)
        #expect(try harness.run("window.__selection.removals").toInt32() == 1)
        #expect(try harness.run(ReaderFind.selectionTextJS).toString() == "")
    }

    /// The reason find is built on WebKit's own search: saved highlights are
    /// anchored by text offsets into this DOM, so nothing find runs in the
    /// page may add, remove or split a node.
    @Test func noFindScriptChangesTheDocument() throws {
        let harness = try ReaderJSHarness(body: article)
        try harness.run(ReaderTemplate.highlightMarksJS)
        #expect(try harness.call("__groveApplyHighlights", [["quick brown"], [String]()]).toInt32() == 1)
        let marked = try harness.bodyHTML
        let text = try harness.bodyText

        try installCountingSelection(in: harness, collapsed: false)
        for script in [
            ReaderFind.pageTextJS,
            ReaderFind.selectionTextJS,
            ReaderFind.anchorSelectionJS,
            ReaderFind.clearSelectionJS,
        ] {
            try harness.run(script)
            #expect(try harness.bodyHTML == marked)
            #expect(try harness.bodyText == text)
        }
    }
}

// MARK: - Session

/// The find session's state machine: what reaches the reading surface, when
/// Return searches versus steps, and which reports and selections it accepts.
@MainActor
struct ReaderFindSessionTests {

    private func presented(typing query: String = "") -> ReaderFindSession {
        let session = ReaderFindSession()
        session.present()
        session.query = query
        return session
    }

    @Test func presentingShowsTheBarAndAsksForFocusEveryTime() {
        let session = ReaderFindSession()
        #expect(!session.isPresented)
        session.present()
        #expect(session.isPresented)
        let firstFocus = session.focusToken
        // ⌘F with the bar already open: still up, and focus is asked for again.
        session.present()
        #expect(session.isPresented)
        #expect(session.focusToken == firstFocus + 1)
    }

    @Test func typingReachesTheSurfaceOnlyOnceCommitted() {
        let session = presented(typing: "moss")
        #expect(session.activeQuery == "")
        session.commitQuery()
        #expect(session.activeQuery == "moss")
    }

    @Test func committingWhileClosedDoesNothing() {
        let session = ReaderFindSession()
        session.query = "moss"
        session.commitQuery()
        #expect(session.activeQuery == "")
    }

    @Test func returnBeforeTheTypingPauseSearchesInsteadOfStepping() {
        let session = presented(typing: "moss")
        session.findNext()
        #expect(session.activeQuery == "moss")
        #expect(session.forwardToken == 0)
        #expect(session.backwardToken == 0)
    }

    @Test func returnOnACommittedQueryStepsForwardAndShiftReturnBack() {
        let session = presented(typing: "moss")
        session.commitQuery()
        session.findNext()
        session.findNext()
        session.findPrevious()
        #expect(session.forwardToken == 2)
        #expect(session.backwardToken == 1)
        #expect(session.activeQuery == "moss")
    }

    @Test func steppingNeedsAQueryAndAnOpenBar() {
        let empty = presented()
        #expect(!empty.canStep)
        empty.findNext()
        empty.findPrevious()
        #expect(empty.forwardToken == 0)
        #expect(empty.backwardToken == 0)

        let closed = ReaderFindSession()
        closed.query = "moss"
        closed.findNext()
        #expect(closed.forwardToken == 0)
        #expect(closed.activeQuery == "")
    }

    @Test func aReportForTheActiveQueryBecomesTheStatus() {
        let session = presented(typing: "moss")
        session.commitQuery()
        session.report(.matches(count: 12, current: nil), for: "moss")
        #expect(session.status == .matches(count: 12, current: nil))
        #expect(session.statusLabel == "12 matches")
    }

    @Test func aReportForASupersededQueryIsDropped() {
        let session = presented(typing: "mos")
        session.commitQuery()
        session.query = "moss"
        session.commitQuery()
        session.report(.matches(count: 40, current: nil), for: "mos")
        #expect(session.status == .idle)
        session.report(.noMatches, for: "moss")
        #expect(session.status == .noMatches)
    }

    @Test func thePreviousCountStaysUpUntilTheNewOneLands() {
        let session = presented(typing: "mos")
        session.commitQuery()
        session.report(.matches(count: 40, current: nil), for: "mos")
        session.query = "moss"
        session.commitQuery()
        #expect(session.status == .matches(count: 40, current: nil))
        session.report(.matches(count: 12, current: nil), for: "moss")
        #expect(session.status == .matches(count: 12, current: nil))
    }

    @Test func emptyingTheFieldClearsTheStatusAtOnce() {
        let session = presented(typing: "moss")
        session.commitQuery()
        session.report(.matches(count: 12, current: nil), for: "moss")
        session.query = ""
        session.commitQuery()
        #expect(session.activeQuery == "")
        #expect(session.status == .idle)
        #expect(session.statusLabel == "")
    }

    @Test func dismissingClosesTheBarAndEndsTheSearch() {
        let session = presented(typing: "moss")
        session.commitQuery()
        session.report(.matches(count: 12, current: 3), for: "moss")
        session.dismiss()
        #expect(!session.isPresented)
        #expect(session.query == "")
        // An empty active query is what tells the surface to drop its match.
        #expect(session.activeQuery == "")
        #expect(session.status == .idle)
        // A late answer from the surface does not bring the status back.
        session.report(.matches(count: 12, current: 3), for: "moss")
        #expect(session.status == .idle)
    }

    @Test func aSurfaceSwitchForgetsTheOldSurfacesCount() {
        let session = presented(typing: "moss")
        session.commitQuery()
        session.report(.matches(count: 12, current: nil), for: "moss")
        session.surfaceDidChange()
        #expect(session.status == .idle)
        #expect(session.activeQuery == "moss")
        #expect(session.isPresented)
    }

    // MARK: Selection ownership

    @Test func theMatchForTheActiveQueryIsFindsSelection() {
        let session = presented(typing: "moss")
        session.commitQuery()
        #expect(session.ownsSelection("Moss"))
        #expect(!session.ownsSelection("moss grows slowly"))
        #expect(!session.ownsSelection(nil))
    }

    @Test func aLateMatchForThePreviousQueryIsStillFindsForAMoment() {
        let session = presented(typing: "mos")
        session.commitQuery()
        session.query = "moss"
        session.commitQuery()
        let justAfter = Date().addingTimeInterval(0.2)
        let muchLater = Date().addingTimeInterval(ReaderFindSession.selectionGraceInterval + 5)
        #expect(session.ownsSelection("mos", now: justAfter))
        #expect(!session.ownsSelection("mos", now: muchLater))
        // The active query's own match is find's for as long as it is active.
        #expect(session.ownsSelection("moss", now: muchLater))
    }

    @Test func withTheBarClosedEverySelectionIsTheReaders() {
        let session = presented(typing: "moss")
        session.commitQuery()
        session.dismiss()
        #expect(!session.ownsSelection("moss"))
    }
}

// MARK: - Window routing

/// ⌘F as the window resolves it from its own state.
@MainActor
struct FindShortcutRoutingTests {

    /// A window with an item open in the reader. The context is handed back
    /// so the item's store stays alive for as long as the test holds it.
    private func makeOpenReader() throws -> (viewModel: ContentViewModel, context: ModelContext) {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "FindShortcutRoutingTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let item = Item(title: "Moss", type: .article)
        item.sourceURL = "https://example.com/moss"
        context.insert(item)
        let viewModel = ContentViewModel()
        viewModel.openedItem = item
        return (viewModel, context)
    }

    @Test func withNothingOpenFindIsLibrarySearch() {
        let viewModel = ContentViewModel()
        #expect(viewModel.findShortcutTarget == .library)
    }

    @Test func onTheItemOverviewFindIsLibrarySearch() throws {
        let window = try makeOpenReader()
        #expect(window.viewModel.findShortcutTarget == .library)
    }

    @Test func inTheWebPaneFindGoesToTheArticle() throws {
        let window = try makeOpenReader()
        window.viewModel.isArticleWebViewActive = true
        #expect(window.viewModel.findShortcutTarget == .article)
    }

    @Test func inThePDFPaneFindGoesToTheDocument() throws {
        let window = try makeOpenReader()
        window.viewModel.isPDFReaderActive = true
        #expect(window.viewModel.findShortcutTarget == .article)
    }

    @Test func anOverlayOverTheReaderKeepsFindOnTheLibrary() throws {
        let window = try makeOpenReader()
        let viewModel = window.viewModel
        viewModel.isArticleWebViewActive = true

        viewModel.showSearch = true
        #expect(viewModel.findShortcutTarget == .library)

        viewModel.showSearch = false
        viewModel.showCaptureOverlay = true
        #expect(viewModel.findShortcutTarget == .library)

        viewModel.showCaptureOverlay = false
        #expect(viewModel.findShortcutTarget == .article)
    }

    @Test func aSurfaceFlagLeftOverWithNoReaderDoesNotCapture() {
        let viewModel = ContentViewModel()
        viewModel.isArticleWebViewActive = true
        #expect(viewModel.findShortcutTarget == .library)
    }
}
