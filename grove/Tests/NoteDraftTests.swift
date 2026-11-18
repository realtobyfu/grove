import Foundation
import SwiftData
import Testing
@testable import grove

/// The draft behind both note surfaces: when it creates a note, when it
/// writes, and when it cleans up after itself.
@MainActor
struct NoteDraftTests {
    @Test func aNewDraftCreatesItsNoteOnFirstSaveAndUpdatesItAfterwards() throws {
        let context = try makeContext()
        let draft = NoteDraft()
        draft.configure(item: nil, boardID: nil, modelContext: context)

        // Nothing written: nothing stored.
        #expect(draft.save() == nil)
        #expect(draft.state == .empty)

        draft.content = "First thought"
        draft.textDidChange()
        #expect(draft.state == .edited)

        let note = try #require(draft.save())
        #expect(draft.state == .saved)
        #expect(note.type == .note)
        #expect(note.status == .active)
        #expect(note.title == NoteDraft.untitledTitle)
        #expect(note.content == "First thought")

        draft.title = "Named"
        #expect(draft.save()?.id == note.id)
        #expect(note.title == "Named")

        let stored: [Item] = context.fetchAll()
        #expect(stored.count == 1)
    }

    @Test func aNewDraftJoinsTheBoardItWasStartedIn() throws {
        let context = try makeContext()
        let board = Board(title: "Reading")
        context.insert(board)
        try context.save()

        let draft = NoteDraft()
        draft.configure(item: nil, boardID: board.id, modelContext: context)
        draft.title = "On reading"

        let note = try #require(draft.save())
        #expect(note.boards.map(\.id) == [board.id])
    }

    @Test func openingAnUntitledNoteShowsAnEmptyTitleAndLeavesTheNoteAlone() throws {
        let context = try makeContext()
        let note = Item(title: NoteDraft.untitledTitle, type: .note)
        note.content = "body"
        context.insert(note)
        try context.save()
        let stamp = note.updatedAt

        let draft = NoteDraft()
        draft.configure(item: note, boardID: nil, modelContext: context)
        #expect(draft.title.isEmpty)
        #expect(draft.content == "body")
        #expect(draft.state == .saved)

        // Opening and closing without typing is not an edit.
        draft.textDidChange()
        #expect(draft.state == .saved)
        #expect(draft.finish()?.id == note.id)
        #expect(note.title == NoteDraft.untitledTitle)
        #expect(note.updatedAt == stamp)
    }

    @Test func aFreshNoteLeftEmptyIsRemovedButOneWithTextIsKept() throws {
        let context = try makeContext()

        let abandoned = Item(title: NoteDraft.untitledTitle, type: .note)
        context.insert(abandoned)
        let written = Item(title: NoteDraft.untitledTitle, type: .note)
        context.insert(written)
        try context.save()
        let writtenID = written.id

        let emptyDraft = NoteDraft()
        emptyDraft.configure(item: abandoned, boardID: nil, modelContext: context, isFresh: true)
        #expect(emptyDraft.finish() == nil)

        let keptDraft = NoteDraft()
        keptDraft.configure(item: written, boardID: nil, modelContext: context, isFresh: true)
        keptDraft.content = "Something worth keeping"
        #expect(keptDraft.finish()?.id == writtenID)

        let stored: [Item] = context.fetchAll()
        #expect(stored.map(\.id) == [writtenID])
    }

    @Test func emptyingAnExistingNoteClearsItRatherThanDeletingIt() throws {
        let context = try makeContext()
        let note = Item(title: "Kept", type: .note)
        note.content = "old text"
        context.insert(note)
        try context.save()

        let draft = NoteDraft()
        draft.configure(item: note, boardID: nil, modelContext: context)
        draft.title = ""
        draft.content = "   "

        #expect(draft.finish()?.id == note.id)
        #expect(note.title == NoteDraft.untitledTitle)
        #expect(note.content == nil)
        let stored: [Item] = context.fetchAll()
        #expect(stored.count == 1)
    }

    @Test func aRenameMadeElsewhereSurvivesTheNextSave() throws {
        let context = try makeContext()
        let note = Item(title: "Before", type: .note)
        note.content = "  body with stray whitespace  "
        context.insert(note)
        try context.save()
        let stamp = note.updatedAt

        let draft = NoteDraft()
        draft.configure(item: note, boardID: nil, modelContext: context)
        // Untrimmed stored text is not, by itself, an edit.
        draft.textDidChange()
        #expect(draft.state == .saved)
        #expect(note.updatedAt == stamp)

        // The inspector renames the note while the page is open…
        note.title = "After"
        // …and the writer carries on in the body.
        draft.content = "body, continued"
        #expect(draft.save()?.id == note.id)

        #expect(note.title == "After")
        #expect(draft.title == "After")
        #expect(note.content == "body, continued")
    }

    private func makeContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration("NoteDraftTests", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
