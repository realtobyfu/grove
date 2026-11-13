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
    var showChatPanel = false
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
    var savedInspectorOverride: Bool?
    var savedChatPanel: Bool?

    // MARK: - Computed Properties

    var isInspectorVisible: Bool {
        if let override = inspectorUserOverride {
            return override
        }
        return selectedItem != nil || openedItem != nil
    }

    /// The item the inspector would describe. Nil means there is nothing to
    /// inspect, which resolves to `.hidden` — no rail, no placeholder column.
    var inspectorItem: Item? {
        selectedItem ?? openedItem
    }

    /// Single source of truth for the window's one trailing column.
    ///
    /// Writing wins, then Dialectics, then the inspector. Writing sits on top
    /// without clearing the chat or inspector state underneath it, so closing
    /// the writer hands the rail back to whatever it was showing before (or
    /// to nothing, if the rail was closed).
    var rightRailMode: RightRailMode {
        if showWritePanel { return .writing }
        if showChatPanel { return .dialectics }
        if isInspectorVisible, inspectorItem != nil { return .inspector }
        return .hidden
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

    // MARK: - Rail Toggles

    /// Toolbar / menu "Write". Opening replaces the rail's current mode;
    /// closing returns it to the previous one.
    func toggleWritePanel() {
        withAnimation(RightRailMetrics.widthChange) {
            writePanelPrompt = nil
            showWritePanel.toggle()
        }
    }

    /// Open the writer, optionally seeded with a prompt.
    func openWritePanel(prompt: String? = nil) {
        withAnimation(RightRailMetrics.widthChange) {
            writePanelPrompt = prompt
            showWritePanel = true
        }
    }

    /// Asking for chat while the writer holds the rail means "show chat",
    /// never "toggle the chat hidden underneath the writer".
    func toggleChatPanel() {
        withAnimation(RightRailMetrics.widthChange) {
            if showWritePanel {
                showWritePanel = false
                showChatPanel = true
            } else {
                showChatPanel.toggle()
            }
        }
    }

    /// Same rule as chat: while writing, the inspector toggle shows the
    /// inspector rather than flipping state the user can't see.
    func toggleInspector() {
        withAnimation(RightRailMetrics.widthChange) {
            if showWritePanel {
                showWritePanel = false
                inspectorUserOverride = true
            } else {
                inspectorUserOverride = !isInspectorVisible
            }
        }
    }

    // MARK: - Focus Mode

    /// Sidebar collapse and rail change are driven from a single
    /// `withAnimation` on `RightRailMetrics.widthChange` — the same curve and
    /// duration the rail uses for its own width — so the two reflows are one.
    func enterFocusMode() {
        if savedColumnVisibility == nil {
            savedColumnVisibility = columnVisibility
            savedInspectorOverride = inspectorUserOverride
            savedChatPanel = showChatPanel
        }
        withAnimation(RightRailMetrics.widthChange) {
            columnVisibility = .detailOnly
            inspectorUserOverride = false
            showChatPanel = false
        }
    }

    func exitFocusMode() {
        withAnimation(RightRailMetrics.widthChange) {
            columnVisibility = savedColumnVisibility ?? .automatic
            inspectorUserOverride = savedInspectorOverride
            showChatPanel = savedChatPanel ?? false
        }
        savedColumnVisibility = nil
        savedInspectorOverride = nil
        savedChatPanel = nil
    }
}
