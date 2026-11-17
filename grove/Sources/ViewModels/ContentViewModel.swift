import SwiftUI
import SwiftData

/// ViewModel that owns navigation, panel, and UI-toggle state for ContentView.
/// Extracted from ContentView's 19 @State vars to a single @Observable class.
@MainActor
@Observable
final class ContentViewModel {
    // MARK: - Navigation State
    var selection: SidebarItem? = .home
    var selectedItem: Item?
    var openedItem: Item?
    var columnVisibility: NavigationSplitViewVisibility = .automatic
    var selectedConversation: Conversation?

    // MARK: - Panel State
    var showWritePanel = false
    var writePanelPrompt: String?
    var writePanelEditItem: Item?
    /// The note "New Note" created empty a moment ago. Its page removes it
    /// again if it is left with nothing in it.
    var freshNoteID: UUID?
    /// The note the rail writer is in the middle of, once it exists. Kept
    /// while another tab has the right page so that coming back to Note
    /// continues it; cleared when the writer is closed with Done.
    var railNoteInProgress: Item?
    var showChatPanel = false
    /// Whether the open reader's own rail (the reflections list, a reflection
    /// being written, a flashcard draft) is on screen. Reported by
    /// `ItemReaderView`; it is what makes Reflections the active tab.
    var isReaderRailActive = false
    // The write, chat and inspector widths live in `RightRailContainer` — the
    // rail owns one width per mode so a panel can't animate a width of its own.

    // MARK: - UI Toggles
    var showSearch = false
    var showCaptureOverlay = false
    var inspectorUserOverride: Bool?
    var isArticleWebViewActive = false
    var isPDFReaderActive = false

    // MARK: - Internal State
    var readLaterScheduler: ReadLaterRestoreScheduler?
    var savedColumnVisibility: NavigationSplitViewVisibility?

    // MARK: - Computed Properties

    var isInspectorVisible: Bool {
        if let override = inspectorUserOverride {
            return override
        }
        // A note page or a source in the reader opens as the page and
        // nothing else. Info is one click away (its tab, ⌘]) rather than a
        // column that arrives uninvited beside the reading or the writing.
        // It follows the selection by itself only over a list.
        if openedItem != nil { return false }
        return selectedItem != nil
    }

    /// A note is open as a page in the detail column.
    var isNotePageOpen: Bool {
        openedItem?.type == .note
    }

    /// A source (article, video, document) is open in the reader — as
    /// opposed to a list, or a note page.
    var isReadingSource: Bool {
        openedItem != nil && !isNotePageOpen
    }

    /// The item the inspector would describe. Nil means there is nothing to
    /// inspect, which resolves to `.hidden` — no rail, no placeholder column.
    var inspectorItem: Item? {
        selectedItem ?? openedItem
    }

    /// Single source of truth for the window's one trailing column.
    ///
    /// Writing wins, then Dialectics, then the inspector. The tab routes
    /// (`selectRightPageTab`) keep at most one of these set at a time, so the
    /// order only matters for routes that set a flag directly (a deep link
    /// into chat while the writer is up, the inspector following a selection).
    var rightRailMode: RightRailMode {
        if showWritePanel { return .writing }
        if showChatPanel { return .dialectics }
        if isInspectorVisible, inspectorItem != nil { return .inspector }
        return .hidden
    }

    // MARK: - Right Page Tabs

    /// The tabs on offer. Reflections belongs to a source open in the reader.
    var rightPageTabs: [RightPageTab] {
        isReadingSource ? [.reflections, .note, .chat, .info] : [.note, .chat, .info]
    }

    /// The tab the right page is showing, or nil when the page is closed.
    var activeRightPageTab: RightPageTab? {
        switch rightRailMode {
        case .writing: return .note
        case .dialectics: return .chat
        case .inspector: return .info
        default: return isReadingSource && isReaderRailActive ? .reflections : nil
        }
    }

    /// Info needs something to describe; Reflections needs a source.
    func isRightPageTabAvailable(_ tab: RightPageTab) -> Bool {
        switch tab {
        case .info: inspectorItem != nil
        case .reflections: isReadingSource
        case .note, .chat: true
        }
    }

    /// A tab was picked. The one already showing closes the page; any other
    /// takes the page over. Nothing is lost either way: the note is saved and
    /// resumed, the conversation stays selected.
    func selectRightPageTab(_ tab: RightPageTab) {
        guard isRightPageTabAvailable(tab) else { return }
        if activeRightPageTab == tab {
            closeRightPage()
            return
        }
        switch tab {
        case .note: showNoteTab()
        case .chat: showChatTab()
        case .info: showInspector()
        case .reflections: showReflectionsTab()
        }
    }

    /// Close the right page — all of it. Nothing waiting underneath (the
    /// inspector for the selection, the reader's reflections) slides in to
    /// take its place; the next tab picked opens it again.
    func closeRightPage() {
        withAnimation(RightRailMetrics.widthChange) {
            showWritePanel = false
            showChatPanel = false
            inspectorUserOverride = false
        }
        if isReadingSource {
            NotificationCenter.default.post(name: .groveSetReaderRailVisible, object: false)
        }
    }

    /// The note the Note tab should pick up again, if there is one that can
    /// be: still in the store, and not the note open as a page beside it.
    private var resumableRailNote: Item? {
        guard let note = railNoteInProgress,
              !note.isDeleted,
              note.modelContext != nil,
              note.id != openedItem?.id else { return nil }
        return note
    }

    private func showNoteTab() {
        withAnimation(RightRailMetrics.widthChange) {
            let resumed = resumableRailNote
            writePanelEditItem = resumed
            if resumed == nil { railNoteInProgress = nil }
            showChatPanel = false
            showWritePanel = true
        }
    }

    private func showChatTab() {
        withAnimation(RightRailMetrics.widthChange) {
            showWritePanel = false
            showChatPanel = true
        }
    }

    private func showReflectionsTab() {
        // The window's page steps aside; the reader brings its own panel up
        // (and opens a new reflection if there are none to list).
        withAnimation(RightRailMetrics.widthChange) {
            showWritePanel = false
            showChatPanel = false
            inspectorUserOverride = false
        }
        NotificationCenter.default.post(name: .groveSetReaderRailVisible, object: true)
    }

    /// The writer was closed from inside (Done, Esc, ⌘↩): that ends the
    /// writing session, so the next Note is a blank one. Another tab taking
    /// the page only sets `showWritePanel` and leaves the session resumable.
    func endNoteSession() {
        withAnimation(RightRailMetrics.widthChange) {
            showWritePanel = false
        }
        writePanelPrompt = nil
        writePanelEditItem = nil
        railNoteInProgress = nil
    }

    /// What ⌘F means right now: the open reader's find bar while an item is up
    /// on a surface that can search itself, library search everywhere else.
    /// The rule itself lives in `ReaderFind.shortcutTarget`.
    var findShortcutTarget: ReaderFind.ShortcutTarget {
        ReaderFind.shortcutTarget(
            readerIsOpen: openedItem != nil,
            surfaceCanFind: isArticleWebViewActive || isPDFReaderActive,
            overlayIsUp: showSearch || showCaptureOverlay
        )
    }

    /// Whether the open reader must keep its own reflections rail out of view.
    ///
    /// The reader's reflections rail is a second `RightRailContainer` inside
    /// the content column. It may only show while the window's rail is
    /// `.hidden`; whenever the window's rail shows anything (writing, chat or
    /// the inspector) the reader's rail resolves to `.hidden` and comes back
    /// when the window's rail closes. That is the whole invariant: sidebar,
    /// content, and at most one trailing column.
    var readerRailYields: Bool {
        rightRailMode != .hidden
    }

    /// The reader asked for its rail (Reflect, a reflection opened for
    /// editing, a flashcard draft, or the reflections panel expanded). Give it
    /// the trailing column by closing whatever the window's rail was showing.
    /// The writer saves its draft when it leaves the rail.
    func claimRailForReader() {
        guard readerRailYields else { return }
        withAnimation(RightRailMetrics.widthChange) {
            showWritePanel = false
            showChatPanel = false
            inspectorUserOverride = false
        }
    }

    // MARK: - Rail Routes

    /// Open a note as a page in the detail column. The rail writer steps
    /// aside if it was holding the rail: the page is the writing surface now.
    func openNotePage(_ note: Item, isFresh: Bool = false) {
        freshNoteID = isFresh ? note.id : nil
        showCaptureOverlay = false
        if showWritePanel {
            withAnimation(RightRailMetrics.widthChange) { showWritePanel = false }
        }
        // The rail's note going to a page ("Page") is the end of its rail
        // session: one note must not be open in two editors at once.
        if railNoteInProgress?.id == note.id {
            railNoteInProgress = nil
            writePanelEditItem = nil
            writePanelPrompt = nil
        }
        selectedItem = note
        openedItem = note
    }

    /// A note has become the open page by some route that set `openedItem`
    /// directly (a list row, Today's Continue, a link) rather than through
    /// `openNotePage`. If it is the note the rail writer has, the rail lets
    /// go of it: one note must not be open in two editors at once.
    func releaseRailNoteIfOpenAsPage() {
        guard let note = openedItem, note.type == .note else { return }
        guard railNoteInProgress?.id == note.id || writePanelEditItem?.id == note.id else { return }
        if showWritePanel {
            withAnimation(RightRailMetrics.widthChange) { showWritePanel = false }
        }
        railNoteInProgress = nil
        writePanelEditItem = nil
        writePanelPrompt = nil
    }

    /// Bring the inspector forward (the note page's "links" control).
    func showInspector() {
        withAnimation(RightRailMetrics.widthChange) {
            showWritePanel = false
            showChatPanel = false
            inspectorUserOverride = true
        }
    }

    /// Open the writer on a new note, optionally answering a prompt ("New
    /// Note", "start writing"). Unlike picking the Note tab this never
    /// resumes: whatever the rail was writing before is already saved.
    func openWritePanel(prompt: String? = nil) {
        withAnimation(RightRailMetrics.widthChange) {
            // A writer already up on the same prompt is the session asked
            // for; anything else starts a fresh one.
            if !showWritePanel || prompt != writePanelPrompt {
                railNoteInProgress = nil
                writePanelEditItem = nil
            }
            writePanelPrompt = prompt
            showChatPanel = false
            showWritePanel = true
        }
    }

    /// Menu "Toggle Chat" (⇧⌘D): the Chat tab.
    func toggleChatPanel() {
        selectRightPageTab(.chat)
    }

    /// Menu "Toggle Inspector" (⌘]): the Info tab.
    func toggleInspector() {
        selectRightPageTab(.info)
    }

    // MARK: - Focus Mode

    /// Reading a source folds the sidebar down to its spine, on the same
    /// curve and duration the right page uses for its own width so the two
    /// reflows are one. Only the sidebar: the right page is left as it is, so
    /// a note or a conversation stays beside whatever is opened next.
    func enterFocusMode() {
        if savedColumnVisibility == nil {
            savedColumnVisibility = columnVisibility
        }
        withAnimation(RightRailMetrics.widthChange) {
            columnVisibility = .detailOnly
        }
    }

    func exitFocusMode() {
        withAnimation(RightRailMetrics.widthChange) {
            columnVisibility = savedColumnVisibility ?? .automatic
        }
        savedColumnVisibility = nil
    }
}
