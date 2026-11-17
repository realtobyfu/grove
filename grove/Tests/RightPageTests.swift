import Foundation
import SwiftData
import Testing
@testable import grove

/// The window's right page: which tabs are offered, which one is showing, and
/// what picking a tab does to the others — in particular that a note being
/// written survives another tab taking the page.
@MainActor
struct RightPageTests {

    /// A window plus a store to put items in. The context is handed back so
    /// the items stay alive for as long as the test holds it.
    private func makeWindow() throws -> (viewModel: ContentViewModel, context: ModelContext) {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "RightPageTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        return (ContentViewModel(), context)
    }

    private func insert(_ title: String, type: ItemType, in context: ModelContext) -> Item {
        let item = Item(title: title, type: type)
        item.status = .active
        context.insert(item)
        return item
    }

    // MARK: - Which tabs

    @Test func aListOffersNoteChatAndInfo() throws {
        let (viewModel, _) = try makeWindow()
        #expect(viewModel.rightPageTabs == [.note, .chat, .info])
    }

    @Test func aSourceInTheReaderAddsReflections() throws {
        let (viewModel, context) = try makeWindow()
        viewModel.openedItem = insert("Moss", type: .article, in: context)
        #expect(viewModel.rightPageTabs == [.reflections, .note, .chat, .info])
    }

    @Test func aNotePageHasNoReflectionsTab() throws {
        let (viewModel, context) = try makeWindow()
        viewModel.openedItem = insert("On moss", type: .note, in: context)
        #expect(viewModel.rightPageTabs == [.note, .chat, .info])
        #expect(!viewModel.isRightPageTabAvailable(.reflections))
    }

    @Test func infoNeedsSomethingToDescribe() throws {
        let (viewModel, context) = try makeWindow()
        #expect(!viewModel.isRightPageTabAvailable(.info))
        viewModel.selectRightPageTab(.info)
        #expect(viewModel.activeRightPageTab == nil)

        viewModel.selectedItem = insert("Moss", type: .article, in: context)
        #expect(viewModel.isRightPageTabAvailable(.info))
    }

    // MARK: - Which one is showing

    @Test func thePageStartsClosed() throws {
        let (viewModel, _) = try makeWindow()
        #expect(viewModel.activeRightPageTab == nil)
        #expect(viewModel.rightRailMode == .hidden)
    }

    @Test func aSelectionBringsInfoUpByItself() throws {
        let (viewModel, context) = try makeWindow()
        viewModel.selectedItem = insert("Moss", type: .article, in: context)
        #expect(viewModel.activeRightPageTab == .info)
    }

    @Test func theReadersOwnRailIsTheReflectionsTab() throws {
        let (viewModel, context) = try makeWindow()
        viewModel.openedItem = insert("Moss", type: .article, in: context)
        viewModel.inspectorUserOverride = false
        viewModel.isReaderRailActive = true
        #expect(viewModel.activeRightPageTab == .reflections)

        // A window tab on top of it is the one showing.
        viewModel.selectRightPageTab(.chat)
        #expect(viewModel.activeRightPageTab == .chat)
    }

    @Test func aStaleReaderRailFlagMeansNothingWithoutAReader() throws {
        let (viewModel, _) = try makeWindow()
        viewModel.isReaderRailActive = true
        #expect(viewModel.activeRightPageTab == nil)
    }

    // MARK: - Picking tabs

    @Test func pickingATabShowsItAndPickingItAgainClosesThePage() throws {
        let (viewModel, _) = try makeWindow()
        viewModel.selectRightPageTab(.chat)
        #expect(viewModel.activeRightPageTab == .chat)
        viewModel.selectRightPageTab(.chat)
        #expect(viewModel.activeRightPageTab == nil)
        #expect(viewModel.rightRailMode == .hidden)
    }

    @Test func closingATabDoesNotRevealTheInspectorUnderneath() throws {
        let (viewModel, context) = try makeWindow()
        viewModel.selectedItem = insert("Moss", type: .article, in: context)
        viewModel.selectRightPageTab(.chat)
        viewModel.selectRightPageTab(.chat)
        #expect(viewModel.rightRailMode == .hidden)
    }

    @Test func oneTabReplacesAnother() throws {
        let (viewModel, _) = try makeWindow()
        viewModel.selectRightPageTab(.chat)
        viewModel.selectRightPageTab(.note)
        #expect(viewModel.activeRightPageTab == .note)
        #expect(!viewModel.showChatPanel)

        // Closing Note closes the page; chat does not come back by itself.
        viewModel.selectRightPageTab(.note)
        #expect(viewModel.activeRightPageTab == nil)

        viewModel.selectRightPageTab(.note)
        viewModel.selectRightPageTab(.chat)
        #expect(viewModel.activeRightPageTab == .chat)
        #expect(!viewModel.showWritePanel)
    }

    @Test func theMenuTogglesAreTheTabs() throws {
        let (viewModel, context) = try makeWindow()
        viewModel.toggleChatPanel()
        #expect(viewModel.activeRightPageTab == .chat)

        // With chat showing, "Toggle Inspector" shows the inspector rather
        // than hiding one that was not on screen.
        viewModel.selectedItem = insert("Moss", type: .article, in: context)
        viewModel.toggleInspector()
        #expect(viewModel.activeRightPageTab == .info)
        viewModel.toggleInspector()
        #expect(viewModel.activeRightPageTab == nil)
    }

    // MARK: - The note survives

    @Test func aNoteInProgressIsPickedUpAgainAfterAnotherTab() throws {
        let (viewModel, context) = try makeWindow()
        viewModel.selectRightPageTab(.note)
        #expect(viewModel.writePanelEditItem == nil)

        // The writer reports its note once autosave has created it.
        let note = insert("Half a thought", type: .note, in: context)
        viewModel.railNoteInProgress = note

        viewModel.selectRightPageTab(.chat)
        #expect(!viewModel.showWritePanel)
        #expect(viewModel.railNoteInProgress?.id == note.id)

        viewModel.selectRightPageTab(.note)
        #expect(viewModel.showWritePanel)
        #expect(viewModel.writePanelEditItem?.id == note.id)
    }

    @Test func aPromptStaysWithItsNoteAcrossTabs() throws {
        let (viewModel, _) = try makeWindow()
        viewModel.openWritePanel(prompt: "What did the essay change your mind about?")
        viewModel.selectRightPageTab(.chat)
        viewModel.selectRightPageTab(.note)
        #expect(viewModel.writePanelPrompt == "What did the essay change your mind about?")
    }

    @Test func doneEndsTheSessionSoTheNextNoteIsBlank() throws {
        let (viewModel, context) = try makeWindow()
        viewModel.openWritePanel(prompt: "A prompt")
        viewModel.railNoteInProgress = insert("Finished", type: .note, in: context)

        viewModel.endNoteSession()
        #expect(!viewModel.showWritePanel)
        #expect(viewModel.railNoteInProgress == nil)
        #expect(viewModel.writePanelPrompt == nil)

        viewModel.selectRightPageTab(.note)
        #expect(viewModel.writePanelEditItem == nil)
    }

    @Test func newNoteNeverResumes() throws {
        let (viewModel, context) = try makeWindow()
        viewModel.selectRightPageTab(.note)
        viewModel.railNoteInProgress = insert("Earlier", type: .note, in: context)
        viewModel.selectRightPageTab(.chat)

        viewModel.openWritePanel()
        #expect(viewModel.activeRightPageTab == .note)
        #expect(viewModel.writePanelEditItem == nil)
        #expect(viewModel.railNoteInProgress == nil)
    }

    @Test func aNoteMovedToAPageLeavesTheRail() throws {
        let (viewModel, context) = try makeWindow()
        viewModel.selectRightPageTab(.note)
        let note = insert("Outgrew the rail", type: .note, in: context)
        viewModel.railNoteInProgress = note

        viewModel.openNotePage(note)
        #expect(!viewModel.showWritePanel)
        #expect(viewModel.railNoteInProgress == nil)

        // Note beside its own page starts a different, blank note.
        viewModel.selectRightPageTab(.note)
        #expect(viewModel.writePanelEditItem == nil)
    }

    @Test func aDeletedNoteIsNotResumed() throws {
        let (viewModel, context) = try makeWindow()
        let note = insert("Gone", type: .note, in: context)
        try context.save()
        viewModel.railNoteInProgress = note
        context.delete(note)
        try context.save()

        viewModel.selectRightPageTab(.note)
        #expect(viewModel.writePanelEditItem == nil)
        #expect(viewModel.railNoteInProgress == nil)
    }

    // MARK: - Labels

    @Test func helpTextNamesTheActionAndTheShortcut() {
        #expect(RightPageTab.chat.helpText(isActive: false) == "Show Chat (\u{21E7}\u{2318}D)")
        #expect(RightPageTab.info.helpText(isActive: true) == "Hide Info (\u{2318}])")
        #expect(RightPageTab.note.helpText(isActive: false) == "Show Note")
    }
}
