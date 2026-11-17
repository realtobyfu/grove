import Foundation
import SwiftData
import Testing
@testable import grove

/// The trail a board page reads as: numbered sources, notes in place.
@MainActor
struct BoardTrailTests {

    // MARK: - Helpers

    private func makeInMemoryModelContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "BoardTrailTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @discardableResult
    private func add(
        _ title: String,
        _ type: ItemType,
        to board: Board,
        in context: ModelContext,
        status: ItemStatus = .active
    ) -> Item {
        let item = Item(title: title, type: type)
        item.status = status
        context.insert(item)
        board.items.append(item)
        return item
    }

    private func numbers(_ trail: BoardTrail) -> [Int?] {
        trail.entries.map { entry in
            switch entry {
            case .source(let number, _): return number
            case .note: return nil
            }
        }
    }

    // MARK: - Splitting sources and notes

    @Test func sourcesAreNumberedAndNotesStayInPlace() throws {
        let context = try makeInMemoryModelContext()
        let board = Board(title: "Tools for thought")
        context.insert(board)
        let bush = add("As We May Think", .article, to: board, in: context)
        let demo = add("The Mother of All Demos", .video, to: board, in: context)
        let trails = add("Trails, not folders", .note, to: board, in: context)
        let matuschak = add("Transformative tools for thought", .article, to: board, in: context)
        let memex = add("What the memex got right", .note, to: board, in: context)

        let trail = BoardTrail(orderedItems: [bush, demo, trails, matuschak, memex])

        #expect(trail.entries.map(\.id) == [bush.id, demo.id, trails.id, matuschak.id, memex.id])
        // Notes take no number, and do not use one up.
        #expect(numbers(trail) == [1, 2, nil, 3, nil])
        #expect(trail.entries.map(\.isSource) == [true, true, false, true, false])
        #expect(trail.sourceCount == 3)
        #expect(trail.noteCount == 2)
    }

    @Test func everyTypeButANoteIsASource() throws {
        let context = try makeInMemoryModelContext()
        let board = Board(title: "Mixed")
        context.insert(board)
        let items = [
            add("Article", .article, to: board, in: context),
            add("Repo", .codebase, to: board, in: context),
            add("Talk", .video, to: board, in: context),
            add("Lecture 3", .courseLecture, to: board, in: context),
        ]

        let trail = BoardTrail(orderedItems: items)

        #expect(numbers(trail) == [1, 2, 3, 4])
        #expect(trail.noteCount == 0)
    }

    @Test func anEmptyBoardIsAnEmptyTrail() {
        let trail = BoardTrail(orderedItems: [])

        #expect(trail.entries.isEmpty)
        #expect(trail.sourceCount == 0)
        #expect(trail.noteCount == 0)
        #expect(trail.countsLine.isEmpty)
    }

    /// The trail is handed the board's manual order by the same helper the
    /// grid and the list use, so it follows `Board.setManualOrder`.
    @Test func trailFollowsTheBoardsManualOrder() throws {
        let context = try makeInMemoryModelContext()
        let board = Board(title: "Manual")
        context.insert(board)
        let article = add("Article", .article, to: board, in: context)
        let note = add("Note", .note, to: board, in: context)
        let video = add("Video", .video, to: board, in: context)
        add("Archived", .article, to: board, in: context, status: .archived)
        board.setManualOrder([video.id, note.id, article.id])

        let ordered = MobileBoardDetailView.sortedItems(
            MobileBoardDetailView.effectiveItems(for: board),
            for: board,
            sortOption: .manual
        )
        let trail = BoardTrail(orderedItems: ordered)

        #expect(trail.entries.map(\.id) == [video.id, note.id, article.id])
        #expect(numbers(trail) == [1, nil, 2])
    }

    // MARK: - Counts line

    @Test func countsLineNamesSourcesAndNotes() {
        #expect(BoardTrail.countsLine(sources: 4, notes: 2) == "4 sources \u{00B7} 2 notes")
        #expect(BoardTrail.countsLine(sources: 1, notes: 1) == "1 source \u{00B7} 1 note")
    }

    @Test func countsLineLeavesOutAnEmptyKind() {
        #expect(BoardTrail.countsLine(sources: 3, notes: 0) == "3 sources")
        #expect(BoardTrail.countsLine(sources: 0, notes: 1) == "1 note")
        #expect(BoardTrail.countsLine(sources: 0, notes: 0) == "")
    }

    @Test func descriptionIsTrimmedAndBlankMeansNone() {
        #expect(BoardTrail.descriptionText("  How people imagined thinking machines.\n")
            == "How people imagined thinking machines.")
        #expect(BoardTrail.descriptionText("   \n") == nil)
        #expect(BoardTrail.descriptionText(nil) == nil)
    }

    // MARK: - Source rows

    @Test func typeLabelsAreShortWords() {
        #expect(BoardTrail.typeLabel(for: Item(title: "A", type: .article)) == "Article")
        #expect(BoardTrail.typeLabel(for: Item(title: "V", type: .video)) == "Video")
        #expect(BoardTrail.typeLabel(for: Item(title: "C", type: .codebase)) == "Code")
        #expect(BoardTrail.typeLabel(for: Item(title: "L", type: .courseLecture)) == "Lecture")

        let paper = Item(title: "Paper", type: .article)
        paper.sourceURL = "https://example.com/paper.pdf"
        #expect(BoardTrail.typeLabel(for: paper) == "PDF")
    }

    @Test func sourceMetaIsTheDomainWithoutWWW() {
        let article = Item(title: "As We May Think", type: .article)
        article.sourceURL = "https://www.theatlantic.com/magazine/archive/1945/07/as-we-may-think/303881/"

        #expect(BoardTrail.sourceMeta(for: article) == "theatlantic.com")
    }

    @Test func sourceMetaAddsAVideosDuration() {
        let video = Item(title: "The Mother of All Demos", type: .video)
        video.sourceURL = "https://www.youtube.com/watch?v=yJDv-zdhzMY"
        video.videoDurationSeconds = 6000

        #expect(BoardTrail.sourceMeta(for: video) == "youtube.com \u{00B7} 1:40:00")
    }

    @Test func sourceMetaIsNilWithoutAWebAddress() {
        let bare = Item(title: "No link", type: .article)
        #expect(BoardTrail.sourceMeta(for: bare) == nil)

        let imported = Item(title: "Imported", type: .article)
        imported.sourceURL = "file:///Users/someone/Documents/paper.pdf"
        #expect(BoardTrail.sourceMeta(for: imported) == nil)
    }

    @Test func aLocalVideoShowsItsDurationButNoDomain() {
        let video = Item(title: "Screen recording", type: .video)
        video.sourceURL = "/Users/someone/Movies/recording.mov"
        video.isVideoLocalFile = true
        video.videoDurationSeconds = 95

        #expect(BoardTrail.sourceMeta(for: video) == "1:35")
    }

    // MARK: - Note excerpt

    @Test func aShortNoteIsShownWhole() {
        let note = "Bush never describes a filing system.\n\nWhat he cares about is the **trail**."

        #expect(BoardTrail.noteExcerpt(of: note) == note)
    }

    @Test func anEmptyNoteHasNoExcerpt() {
        #expect(BoardTrail.noteExcerpt(of: nil) == "")
        #expect(BoardTrail.noteExcerpt(of: "  \n\n ") == "")
    }

    @Test func aLongNoteIsCutAtALineBoundary() {
        let lines = (1...10).map { "Line \($0)" }
        let note = lines.joined(separator: "\n")

        let excerpt = BoardTrail.noteExcerpt(of: note, maxLines: 4, charactersPerLine: 80)

        #expect(excerpt == "Line 1\nLine 2\nLine 3\nLine 4")
    }

    @Test func aLongParagraphCountsForTheLinesItWraps() {
        let long = String(repeating: "word ", count: 40).trimmingCharacters(in: .whitespaces)
        let note = "\(long)\n\nSecond paragraph.\n\nThird paragraph."

        // 199 characters at 80 a line is three lines; one more fits.
        let excerpt = BoardTrail.noteExcerpt(of: note, maxLines: 4, charactersPerLine: 80)

        #expect(excerpt == "\(long)\n\nSecond paragraph.")
    }

    @Test func theFirstLineIsKeptHoweverLongItIs() {
        let long = String(repeating: "a", count: 1_000)

        let excerpt = BoardTrail.noteExcerpt(of: "\(long)\n\nMore.", maxLines: 4, charactersPerLine: 80)

        #expect(excerpt == long)
    }

    @Test func aCodeFenceLeftOpenByTheCutIsClosed() {
        let note = """
        Intro.

        ```swift
        let a = 1
        let b = 2
        let c = 3
        ```

        Outro.
        """

        let excerpt = BoardTrail.noteExcerpt(of: note, maxLines: 4, charactersPerLine: 80)

        #expect(excerpt == "Intro.\n\n```swift\nlet a = 1\nlet b = 2\n```")
    }

    @Test func aFenceOpenedOnTheLastKeptLineIsDropped() {
        let note = "One.\nTwo.\n\n```swift\nlet a = 1\n```"

        let excerpt = BoardTrail.noteExcerpt(of: note, maxLines: 3, charactersPerLine: 80)

        #expect(excerpt == "One.\nTwo.")
    }

    // MARK: - View mode

    @Test func trailIsTheFirstOfThreeViewModes() {
        #expect(BoardViewMode.allCases == [.trail, .grid, .list])
        #expect(BoardViewMode.allCases.map(\.title) == ["Trail", "Grid", "List"])
    }
}
