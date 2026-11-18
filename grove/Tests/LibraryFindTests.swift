import Foundation
import SwiftData
import Testing
@testable import grove

/// The Library as the place you search: the snippet cut around a match, the
/// headings search hits are sorted under, and the fresh corpus the find field
/// asks `SearchViewModel` for.
struct LibraryFindTests {
    private typealias Snippet = LibraryFind.Snippet
    private typealias Candidate = LibraryFind.Candidate<String>

    private let ellipsis = "\u{2026}"

    // MARK: - Snippet

    @Test func aSnippetSplitsTheLineAroundTheMatch() {
        let snippet = LibraryFind.snippet(
            in: "Engelbart's word was augment, not automate.",
            matching: "augment"
        )

        #expect(snippet == Snippet(before: "Engelbart's word was ", match: "augment", after: ", not automate."))
        #expect(snippet?.text == "Engelbart's word was augment, not automate.")
    }

    @Test func theMatchIgnoresCaseAndKeepsTheTextsOwnSpelling() {
        let snippet = LibraryFind.snippet(
            in: "Engelbart's word was AUGMENT, not automate.",
            matching: "  augment "
        )

        #expect(snippet?.match == "AUGMENT")
    }

    @Test func aMatchInsideAWordMarksOnlyTheMatchedLetters() {
        let snippet = LibraryFind.snippet(
            in: "closer to augmentation than to partnership",
            matching: "augment"
        )

        #expect(snippet == Snippet(before: "closer to ", match: "augment", after: "ation than to partnership"))
    }

    @Test func aLongLineIsCutAtWholeWordsAndMarkedWithEllipses() {
        let text = "one two three four five six seven eight nine ten"

        // The allowance ends exactly on word boundaries: nothing more is dropped.
        let onBoundaries = LibraryFind.snippet(in: text, matching: "six", lead: 10, trail: 12)
        #expect(onBoundaries == Snippet(
            before: ellipsis + "four five ",
            match: "six",
            after: " seven eight" + ellipsis
        ))

        // The allowance ends inside "four" and "eight": both are left out whole.
        let insideWords = LibraryFind.snippet(in: text, matching: "six", lead: 9, trail: 11)
        #expect(insideWords == Snippet(
            before: ellipsis + "five ",
            match: "six",
            after: " seven" + ellipsis
        ))
    }

    @Test func aLineThatFitsCarriesNoEllipsis() {
        let text = "one two three four five six seven eight nine ten"

        let snippet = LibraryFind.snippet(in: text, matching: "six", lead: 100, trail: 100)

        #expect(snippet == Snippet(
            before: "one two three four five ",
            match: "six",
            after: " seven eight nine ten"
        ))
    }

    @Test func contextStaysOnTheLineOfTheMatch() {
        let text = "# Heading\n\nFirst line here.\nThe word augment sits on line two.\nThird line."

        let snippet = LibraryFind.snippet(in: text, matching: "augment")

        // Whole line, so no ellipsis at either end.
        #expect(snippet == Snippet(before: "The word ", match: "augment", after: " sits on line two."))
    }

    @Test func aCutInsideTheLineStillStopsAtTheLinesEnds() {
        let text = "First line.\nSecond line has the word here.\nThird."

        let snippet = LibraryFind.snippet(in: text, matching: "word", lead: 6, trail: 4)

        #expect(snippet == Snippet(before: ellipsis + "the ", match: "word", after: ellipsis))
    }

    @Test func whitespaceRunsBecomeSingleSpaces() {
        let snippet = LibraryFind.snippet(in: "alpha   beta\t gamma", matching: "beta")

        #expect(snippet == Snippet(before: "alpha ", match: "beta", after: " gamma"))
    }

    @Test func aWordLongerThanTheLeadIsDroppedRatherThanCutInTwo() {
        let snippet = LibraryFind.snippet(
            in: "supercalifragilisticexpialidocious augment",
            matching: "augment",
            lead: 5,
            trail: 5
        )

        #expect(snippet == Snippet(before: ellipsis, match: "augment", after: ""))
    }

    @Test func aQueryOfSeveralWordsFallsBackToItsEarliestWord() {
        // The words occur together: the whole phrase is the match.
        let together = LibraryFind.snippet(in: "man computer symbiosis", matching: "computer symbiosis")
        #expect(together == Snippet(before: "man ", match: "computer symbiosis", after: ""))

        // They do not: the earliest of them is.
        let apart = LibraryFind.snippet(in: "tools for the human intellect", matching: "intellect human")
        #expect(apart == Snippet(before: "tools for the ", match: "human", after: " intellect"))
    }

    @Test func noOccurrenceGivesNoSnippet() {
        #expect(LibraryFind.snippet(in: "nothing here", matching: "augment") == nil)
        #expect(LibraryFind.snippet(in: "", matching: "augment") == nil)
        #expect(LibraryFind.snippet(in: "augment", matching: "   ") == nil)
    }

    @Test func theWholeTextCanBeTheMatch() {
        #expect(LibraryFind.snippet(in: "augment", matching: "augment")
            == Snippet(before: "", match: "augment", after: ""))
    }

    // MARK: - Excerpt

    @Test func anExcerptIsTheFirstLineWithAnythingOnIt() {
        let excerpt = LibraryFind.excerpt(of: "\n\n  The first line of the note.\nSecond line.")

        #expect(excerpt == Snippet(before: "The first line of the note.", match: "", after: ""))
    }

    @Test func aLongFirstLineIsCutAtAWordAndMarked() {
        let text = "one two three four five"

        #expect(LibraryFind.excerpt(of: text, length: 7)?.before == "one two" + ellipsis)
        #expect(LibraryFind.excerpt(of: text, length: 8)?.before == "one two" + ellipsis)
        #expect(LibraryFind.excerpt(of: "one two three", length: 13)?.before == "one two three")
        #expect(LibraryFind.excerpt(of: "abcdefghijkl mno", length: 5)?.before == "abcde" + ellipsis)
    }

    @Test func blankTextHasNoExcerpt() {
        #expect(LibraryFind.excerpt(of: "") == nil)
        #expect(LibraryFind.excerpt(of: "   \n ") == nil)
    }

    // MARK: - Markdown

    @Test func aLineOfMarkdownLosesItsMarksAndKeepsItsWords() {
        #expect(LibraryFind.plainLine("## A heading") == "A heading")
        #expect(LibraryFind.plainLine("> quoted words") == "quoted words")
        #expect(LibraryFind.plainLine("> > nested quote") == "nested quote")
        #expect(LibraryFind.plainLine("- a bullet") == "a bullet")
        #expect(LibraryFind.plainLine("* another bullet") == "another bullet")
        #expect(LibraryFind.plainLine("  + indented bullet") == "indented bullet")
        #expect(LibraryFind.plainLine("- [x] done task") == "done task")
        #expect(LibraryFind.plainLine("3. numbered") == "numbered")
        #expect(LibraryFind.plainLine("> - quoted bullet") == "quoted bullet")
        #expect(LibraryFind.plainLine("some **bold** and *italic* and `code`") == "some bold and italic and code")
        #expect(LibraryFind.plainLine("~~struck~~ and _under_") == "struck and under")
        #expect(LibraryFind.plainLine("see [the essay](https://example.com) now") == "see the essay now")
        #expect(LibraryFind.plainLine("![a figure](fig.png)") == "a figure")
        #expect(LibraryFind.plainLine("linked to [[As We May Think]]") == "linked to As We May Think")
        #expect(LibraryFind.plainLine("[[As We May Think|Bush]] said") == "Bush said")
    }

    @Test func plainTextIsLeftAlone() {
        #expect(LibraryFind.plainLine("A plain line, with commas.") == "A plain line, with commas.")
        #expect(LibraryFind.plainLine("snake_case stays whole") == "snake_case stays whole")
        #expect(LibraryFind.plainLine("2024 was a year") == "2024 was a year")
        #expect(LibraryFind.plainLine("-not a bullet") == "-not a bullet")
        #expect(LibraryFind.plainLine("```swift") == "")
    }

    @Test func aSnippetFromMarkdownReadsAsProse() {
        let text = "# Notes\n\n- Engelbart's word was **augment**, not [automate](https://x.y)."

        let snippet = LibraryFind.snippet(inMarkdown: text, matching: "augment")

        #expect(snippet == Snippet(before: "Engelbart's word was ", match: "augment", after: ", not automate."))
    }

    @Test func marksInsideAWordDoNotHideTheMatch() {
        let snippet = LibraryFind.snippet(inMarkdown: "**aug**ment", matching: "augment")

        #expect(snippet == Snippet(before: "", match: "augment", after: ""))
    }

    @Test func aMarkdownSnippetFallsBackToTheEarliestWordAsThePlainOneDoes() {
        let text = "> tools for the\n## human intellect"

        #expect(LibraryFind.snippet(inMarkdown: text, matching: "human tools")
            == Snippet(before: "", match: "tools", after: " for the"))
        #expect(LibraryFind.snippet(inMarkdown: text, matching: "nothing") == nil)
        #expect(LibraryFind.snippet(inMarkdown: "", matching: "tools") == nil)
    }

    @Test func aMarkdownExcerptSkipsLinesWithNoWords() {
        let text = "```\n---\n## The first real line\nSecond."

        #expect(LibraryFind.excerpt(ofMarkdown: text) == Snippet(before: "The first real line", match: "", after: ""))
        #expect(LibraryFind.excerpt(ofMarkdown: "---\n***") == nil)
    }

    @Test func groupedTextMatchesAreCutFromThePlainText() {
        let groups = LibraryFind.groups(
            query: "augment",
            exact: [
                item("note", title: "Memex", isNote: true, body: "> a way to **augment** the mind"),
                reflection("reflection", on: "Demos", body: "- [ ] _augment_ it"),
            ],
            related: []
        )

        let rows = groups.flatMap(\.rows)
        #expect(rows.first { $0.id == "note" }?.snippet?.text == "a way to augment the mind")
        #expect(rows.first { $0.id == "reflection" }?.snippet?.text == "augment it")
    }

    // MARK: - Title match

    @Test func aTitleMatchesTheQueryAsTypedOrEveryWordOfIt() {
        #expect(LibraryFind.titleContains("Augmenting Human Intellect", query: "augment"))
        #expect(LibraryFind.titleContains("Augmenting Human Intellect", query: " human intellect "))
        #expect(LibraryFind.titleContains("Intellect of the Human", query: "human intellect"))
        #expect(!LibraryFind.titleContains("Human", query: "human intellect"))
        #expect(!LibraryFind.titleContains("As We May Think", query: "augment"))
        #expect(!LibraryFind.titleContains("As We May Think", query: "  "))
    }

    // MARK: - Groups

    private func item(
        _ id: String,
        itemID: UUID = UUID(),
        title: String,
        isNote: Bool = false,
        body: String = "",
        score: Double = 0.5
    ) -> Candidate {
        Candidate(
            id: id,
            itemID: itemID,
            source: .item,
            title: title,
            isNote: isNote,
            body: body,
            score: score,
            payload: id
        )
    }

    private func reflection(
        _ id: String,
        itemID: UUID = UUID(),
        on title: String,
        body: String,
        score: Double = 0.5
    ) -> Candidate {
        Candidate(
            id: id,
            itemID: itemID,
            source: .reflection,
            title: title,
            isNote: false,
            body: body,
            score: score,
            payload: id
        )
    }

    private func kinds(_ groups: [LibraryFind.ResultGroup<String>]) -> [LibraryFind.GroupKind] {
        groups.map(\.kind)
    }

    private func ids(_ groups: [LibraryFind.ResultGroup<String>], _ kind: LibraryFind.GroupKind) -> [String] {
        groups.first { $0.kind == kind }?.rows.map(\.id) ?? []
    }

    @Test func hitsAreSortedUnderTitlesNotesTextAndRelated() {
        let groups = LibraryFind.groups(
            query: "augment",
            exact: [
                item("title", title: "Augmenting Human Intellect", body: "A conceptual framework."),
                item("note", title: "What the memex got right", isNote: true,
                     body: "Engelbart's word was augment, not automate."),
                item("article", title: "As We May Think", body: "A device to augment memory."),
                reflection("reflection", on: "Man-Computer Symbiosis",
                           body: "closer to augmentation than to partnership"),
            ],
            related: [item("related", title: "The Mother of All Demos")]
        )

        #expect(kinds(groups) == [.titles, .notes, .text, .related])
        #expect(ids(groups, .titles) == ["title"])
        #expect(Set(ids(groups, .notes)) == ["note", "reflection"])
        #expect(ids(groups, .text) == ["article"])
        #expect(ids(groups, .related) == ["related"])
        #expect(groups.map(\.id) == ["titles", "notes", "text", "related"])
    }

    @Test func headingsReadAsInTheDesign() {
        #expect(LibraryFind.GroupKind.titles.title == "Titles")
        #expect(LibraryFind.GroupKind.notes.title == "In your notes and reflections")
        #expect(LibraryFind.GroupKind.text.title == "In the text")
        #expect(LibraryFind.GroupKind.tagged.title == "Tagged")
        #expect(LibraryFind.GroupKind.related.title == "Related in meaning")
        #expect(LibraryFind.boardsGroupTitle == "Boards")
    }

    @Test func titleAndRelatedRowsCarryNoSnippetAndTextMatchesDo() {
        let groups = LibraryFind.groups(
            query: "augment",
            exact: [
                item("title", title: "Augmenting Human Intellect", body: "to augment is the aim"),
                item("note", title: "What the memex got right", isNote: true,
                     body: "Engelbart's word was augment, not automate."),
            ],
            related: [item("related", title: "The Mother of All Demos", body: "augment")]
        )

        let rows = groups.flatMap(\.rows)
        let titleRow = rows.first { $0.id == "title" }
        let relatedRow = rows.first { $0.id == "related" }
        let noteRow = rows.first { $0.id == "note" }

        #expect(rows.count == 3)
        #expect(titleRow?.id == "title")
        #expect(titleRow?.snippet == nil)
        #expect(relatedRow?.id == "related")
        #expect(relatedRow?.snippet == nil)
        #expect(noteRow?.snippet == Snippet(
            before: "Engelbart's word was ",
            match: "augment",
            after: ", not automate."
        ))
    }

    @Test func notesAndReflectionsAreMergedBestScoreFirst() {
        let groups = LibraryFind.groups(
            query: "augment",
            exact: [
                item("weak note", title: "A", isNote: true, body: "to augment", score: 0.42),
                item("strong note", title: "B", isNote: true, body: "augment first", score: 0.63),
                reflection("best reflection", on: "C", body: "augment", score: 1.0),
                reflection("tied reflection", on: "D", body: "we augment", score: 0.42),
            ],
            related: []
        )

        // Equal scores keep the order they arrived in.
        #expect(ids(groups, .notes) == ["best reflection", "strong note", "weak note", "tied reflection"])
    }

    @Test func aReflectionAlwaysShowsItsTextEvenWithoutALiteralMatch() {
        let groups = LibraryFind.groups(
            query: "agmnt",
            exact: [reflection("r", on: "Augment", body: "A loose thought.\nAnd more.")],
            related: []
        )

        #expect(kinds(groups) == [.notes])
        #expect(groups.first?.rows.first?.snippet == Snippet(before: "A loose thought.", match: "", after: ""))
    }

    @Test func aLooseMatchIsATitleHitWhenTheTitleIsWhatMatched() {
        // "agmnt": the letters of "augment" in order, never the word itself.
        let groups = LibraryFind.groups(
            query: "agmnt",
            exact: [
                item("by title", title: "Augment", body: "nothing literal here"),
                item("by text", title: "Zzz", body: "a great many notes"),
                item("no text", title: "Zzz"),
            ],
            related: []
        )

        #expect(ids(groups, .titles) == ["by title", "no text"])
        #expect(ids(groups, .text) == ["by text"])
        #expect(groups.last?.rows.first?.snippet == Snippet(before: "a great many notes", match: "", after: ""))
    }

    @Test func hitsOutsideTheLibrarysScopeAreDropped() {
        let shown = UUID(), hidden = UUID(), hiddenRelated = UUID()

        let groups = LibraryFind.groups(
            query: "augment",
            exact: [
                item("shown", itemID: shown, title: "Augment"),
                item("archived", itemID: hidden, title: "Augmented"),
                reflection("on archived", itemID: hidden, on: "Augmented", body: "augment"),
            ],
            related: [item("related", itemID: hiddenRelated, title: "Elsewhere")],
            allowedItemIDs: [shown]
        )

        #expect(kinds(groups) == [.titles])
        #expect(ids(groups, .titles) == ["shown"])
    }

    @Test func aRelatedItemAlreadyListedIsNotRepeated() {
        let listed = UUID(), byReflection = UUID(), new = UUID()

        let groups = LibraryFind.groups(
            query: "augment",
            exact: [
                item("title", itemID: listed, title: "Augment"),
                reflection("reflection", itemID: byReflection, on: "Symbiosis", body: "augment"),
            ],
            related: [
                item("again", itemID: listed, title: "Augment"),
                item("parent", itemID: byReflection, title: "Symbiosis"),
                item("new", itemID: new, title: "Demos"),
                item("new twice", itemID: new, title: "Demos"),
            ]
        )

        #expect(ids(groups, .related) == ["new"])
    }

    @Test func anItemAndAReflectionOnItAreBothListed() {
        let itemID = UUID()

        let groups = LibraryFind.groups(
            query: "augment",
            exact: [
                item("title", itemID: itemID, title: "Augment"),
                reflection("reflection", itemID: itemID, on: "Augment", body: "to augment"),
            ],
            related: []
        )

        #expect(ids(groups, .titles) == ["title"])
        #expect(ids(groups, .notes) == ["reflection"])
        #expect(groups.flatMap(\.rows).map(\.itemID) == [itemID, itemID])
    }

    @Test func noHitsGiveNoGroups() {
        let none: [Candidate] = []

        #expect(LibraryFind.groups(query: "augment", exact: none, related: none).isEmpty)
    }

    @Test func rowsCarryTheirPayloadThrough() {
        let groups = LibraryFind.groups(
            query: "augment",
            exact: [item("a", title: "Augment")],
            related: [item("b", title: "Demos")]
        )

        #expect(groups.flatMap(\.rows).map(\.payload) == ["a", "b"])
        #expect(groups.flatMap(\.rows).map(\.source) == [.item, .item])
    }

    // MARK: - Tagged

    private func tagged(_ name: String, itemID: UUID, title: String = "Item", score: Double = 0.9) -> Candidate {
        Candidate(
            id: "tag-\(itemID.uuidString)",
            itemID: itemID,
            source: .tag,
            title: title,
            isNote: false,
            body: name,
            score: score,
            payload: "tag-\(itemID.uuidString)"
        )
    }

    @Test func itemsCarryingAMatchingTagAreListedUnderTagged() {
        let first = UUID(), second = UUID()

        let groups = LibraryFind.groups(
            query: "typo",
            exact: [],
            tagged: [tagged("Typography", itemID: first), tagged("typography", itemID: second)],
            related: []
        )

        #expect(kinds(groups) == [.tagged])
        #expect(groups.first?.rows.map(\.itemID) == [first, second])
        #expect(groups.first?.rows.map(\.source) == [.tag, .tag])
        #expect(groups.first?.rows.first?.snippet == Snippet(before: "", match: "Typo", after: "graphy"))
    }

    @Test func anItemWithSeveralMatchingTagsIsListedOnceNamingThemAll() {
        let itemID = UUID()

        let groups = LibraryFind.groups(
            query: "type",
            exact: [],
            tagged: [
                tagged("Typefaces", itemID: itemID),
                tagged("Type design", itemID: itemID),
                tagged("Typefaces", itemID: itemID),
            ],
            related: []
        )

        #expect(ids(groups, .tagged).count == 1)
        #expect(groups.first?.rows.first?.snippet?.text == "Typefaces, Type design")
        #expect(groups.first?.rows.first?.snippet?.match == "Type")
    }

    @Test func aTaggedItemAlreadyListedIsNotRepeatedAndRelatedDoesNotRepeatIt() {
        let listed = UUID(), taggedOnly = UUID()

        let groups = LibraryFind.groups(
            query: "typo",
            exact: [item("title", itemID: listed, title: "Typography notes")],
            tagged: [tagged("typography", itemID: listed), tagged("typography", itemID: taggedOnly)],
            related: [item("again", itemID: taggedOnly, title: "Elsewhere")]
        )

        #expect(kinds(groups) == [.titles, .tagged])
        #expect(groups.last?.rows.map(\.itemID) == [taggedOnly])
    }

    @Test func aTagThatOnlyLooselyMatchesIsLeftOut() {
        // "agmnt" is in "augment" letter by letter, never as typed.
        let groups = LibraryFind.groups(
            query: "agmnt",
            exact: [],
            tagged: [tagged("augment", itemID: UUID())],
            related: []
        )

        #expect(groups.isEmpty)
    }

    @Test func taggedItemsOutsideTheScopeAreDropped() {
        let shown = UUID(), hidden = UUID()

        let groups = LibraryFind.groups(
            query: "typo",
            exact: [],
            tagged: [tagged("typography", itemID: hidden), tagged("typography", itemID: shown)],
            related: [],
            allowedItemIDs: [shown]
        )

        #expect(groups.flatMap(\.rows).map(\.itemID) == [shown])
    }

    @Test func taggedSitsBetweenTheTextAndRelated() {
        let groups = LibraryFind.groups(
            query: "augment",
            exact: [
                item("title", title: "Augment"),
                item("article", title: "As We May Think", body: "to augment memory"),
            ],
            tagged: [tagged("augmentation", itemID: UUID())],
            related: [item("related", title: "Demos")]
        )

        #expect(kinds(groups) == [.titles, .text, .tagged, .related])
    }

    // MARK: - Boards

    private struct BoardStub {
        let id: UUID
        let title: String
    }

    private func offered(_ boards: [BoardStub], query: String, current: UUID? = nil) -> [String] {
        LibraryFind.offeredBoards(boards, query: query, excluding: current, id: { $0.id }, title: { $0.title })
            .map(\.title)
    }

    @Test func boardsWhoseNameHoldsTheQueryAreOfferedInOrder() {
        let boards = [
            BoardStub(id: UUID(), title: "Type design"),
            BoardStub(id: UUID(), title: "Typography"),
            BoardStub(id: UUID(), title: "Tools"),
        ]

        #expect(offered(boards, query: "typ") == ["Type design", "Typography"])
        #expect(offered(boards, query: " TOOLS ") == ["Tools"])
        // Letters in order are not enough.
        #expect(offered(boards, query: "tpgr").isEmpty)
        #expect(offered(boards, query: "  ").isEmpty)
    }

    @Test func theBoardAlreadyFilteredToIsNotOfferedAndNoBoardTwice() {
        let current = BoardStub(id: UUID(), title: "Typography")
        let other = BoardStub(id: UUID(), title: "Typefaces")

        #expect(offered([current, other], query: "typ", current: current.id) == ["Typefaces"])
        #expect(offered([other, other], query: "typ") == ["Typefaces"])
    }

    // MARK: - Keyboard highlight

    @Test func downFromTheFieldLandsOnTheFirstRowAndStopsOnTheLast() {
        let rows = ["a", "b", "c"]

        #expect(LibraryFind.movedHighlight(from: nil, by: 1, in: rows) == "a")
        #expect(LibraryFind.movedHighlight(from: "a", by: 1, in: rows) == "b")
        #expect(LibraryFind.movedHighlight(from: "c", by: 1, in: rows) == "c")
    }

    @Test func upFromTheFirstRowGoesBackToTheField() {
        let rows = ["a", "b", "c"]

        #expect(LibraryFind.movedHighlight(from: "c", by: -1, in: rows) == "b")
        #expect(LibraryFind.movedHighlight(from: "a", by: -1, in: rows) == nil)
        #expect(LibraryFind.movedHighlight(from: nil, by: -1, in: rows) == nil)
    }

    @Test func aHighlightOnARowNoLongerListedStartsAgain() {
        #expect(LibraryFind.movedHighlight(from: "gone", by: 1, in: ["a", "b"]) == "a")
        #expect(LibraryFind.movedHighlight(from: "gone", by: -1, in: ["a", "b"]) == nil)
        #expect(LibraryFind.movedHighlight(from: "a", by: 1, in: []) == nil)
    }

    // MARK: - Count

    @Test func theCountReadsAsAPhrase() {
        #expect(LibraryFind.countLabel(1) == "1 result")
        #expect(LibraryFind.countLabel(6) == "6 results")
        #expect(LibraryFind.countLabel(0) == "0 results")
    }

    // MARK: - SearchViewModel, as the find field drives it

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SharedModelContainer.schema,
            configurations: [ModelConfiguration(
                "LibraryFindTests",
                schema: SharedModelContainer.schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )]
        )
        return ModelContext(container)
    }

    /// A view model over an empty, private embedding index: exact matches only.
    @MainActor
    private func makeViewModel(_ context: ModelContext) -> SearchViewModel {
        let emptyIndex = EmbeddingIndexService(
            cacheURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("library-find-tests-\(UUID().uuidString).json")
        )
        return SearchViewModel(
            modelContext: context,
            debounceNanoseconds: 10_000_000,
            semanticDebounceNanoseconds: 10_000_000,
            embeddingIndex: emptyIndex
        )
    }

    /// The find field stays on screen between searches, so it asks the view
    /// model to read the store again each time. Without that, the corpus the
    /// first search loaded is the one every later search uses.
    @MainActor
    @Test func invalidatingTheCorpusLetsTheNextSearchSeeNewItems() throws {
        let context = try makeContext()
        context.insert(Item(title: "Spaced repetition notes", type: .note))
        try context.save()
        let viewModel = makeViewModel(context)

        viewModel.updateQuery("spaced")
        viewModel.flushPendingSearch()
        #expect(viewModel.results[.item]?.count == 1)

        context.insert(Item(title: "Spaced out", type: .note))
        try context.save()

        // Same view model, same query: the cached corpus does not hold the new note.
        viewModel.flushPendingSearch()
        #expect(viewModel.results[.item]?.count == 1)

        viewModel.invalidateCorpus()
        viewModel.flushPendingSearch()
        #expect(viewModel.results[.item]?.count == 2)
    }

    @MainActor
    @Test func anItemScopeRestrictsItemsAndTheReflectionsOnThem() throws {
        let context = try makeContext()
        let inScope = Item(title: "Spaced out", type: .note)
        let outOfScope = Item(title: "Spaced repetition notes", type: .article)
        context.insert(inScope)
        context.insert(outOfScope)
        context.insert(ReflectionBlock(item: outOfScope, blockType: .keyInsight, content: "spaced thinking"))
        try context.save()
        let viewModel = makeViewModel(context)

        viewModel.updateQuery("spaced")
        viewModel.flushPendingSearch()
        #expect(viewModel.results[.item]?.count == 2)
        #expect(viewModel.results[.reflection]?.count == 1)

        viewModel.scopeItemIDs = [inScope.id]
        viewModel.flushPendingSearch()
        #expect(viewModel.results[.item]?.map(\.title) == ["Spaced out"])
        #expect(viewModel.results[.reflection] == nil)

        // Nil is the overlay's case: everything is searched again.
        viewModel.scopeItemIDs = nil
        viewModel.flushPendingSearch()
        #expect(viewModel.results[.item]?.count == 2)
        #expect(viewModel.results[.reflection]?.count == 1)
    }

    /// Why the Library scopes the search rather than filtering what comes
    /// back: the view model keeps the best fifteen item hits, so a match the
    /// Library is showing can be crowded out by better ones it is not.
    @MainActor
    @Test func theResultLimitAppliesInsideTheScope() throws {
        let context = try makeContext()
        for _ in 0..<16 {
            context.insert(Item(title: "Spaced", type: .article))
        }
        let quiet = Item(title: "Notes on being spaced out", type: .note)
        context.insert(quiet)
        try context.save()
        let viewModel = makeViewModel(context)

        viewModel.updateQuery("spaced")
        viewModel.flushPendingSearch()
        #expect(viewModel.results[.item]?.count == 15)
        let unscoped = viewModel.results[.item] ?? []
        #expect(!unscoped.contains(where: { $0.item?.id == quiet.id }))

        viewModel.scopeItemIDs = [quiet.id]
        viewModel.flushPendingSearch()
        #expect(viewModel.results[.item]?.map(\.title) == ["Notes on being spaced out"])
    }

    // MARK: - Result limits

    @Test func theOverlaysLimitsAreTheDefault() {
        let overlay = SearchResultLimits.overlay

        #expect(overlay.items == 15)
        #expect(overlay.reflections == 10)
        #expect(overlay.tags == 8)
        #expect(overlay.boards == 5)
        #expect(overlay.related == SearchViewModel.semanticResultLimit)
    }

    @Test func theLibraryListsEveryMatchButKeepsRelatedShort() {
        let library = SearchResultLimits.library

        #expect(library.items == .max)
        #expect(library.reflections == .max)
        #expect(library.tags == .max)
        #expect(library.boards == .max)
        #expect(library.related == SearchResultLimits.overlay.related)
    }

    @MainActor
    @Test func aViewModelStartsWithTheOverlaysLimits() throws {
        let viewModel = makeViewModel(try makeContext())

        #expect(viewModel.resultLimits == .overlay)
    }

    @MainActor
    @Test func raisedLimitsListEveryItemAndReflectionMatch() throws {
        let context = try makeContext()
        for index in 0..<20 {
            let item = Item(title: "Spaced \(index)", type: .article)
            context.insert(item)
            context.insert(ReflectionBlock(item: item, blockType: .keyInsight, content: "spaced thought \(index)"))
        }
        try context.save()
        let viewModel = makeViewModel(context)

        viewModel.updateQuery("spaced")
        viewModel.flushPendingSearch()
        #expect(viewModel.results[.item]?.count == 15)
        #expect(viewModel.results[.reflection]?.count == 10)

        viewModel.resultLimits = .library
        viewModel.flushPendingSearch()
        #expect(viewModel.results[.item]?.count == 20)
        #expect(viewModel.results[.reflection]?.count == 20)
    }
}
