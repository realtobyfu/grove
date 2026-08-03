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
    var writePanelWidth: CGFloat = LayoutSettings.width(for: .contentWrite) ?? 480
    var showChatPanel = false
    // The chat and inspector widths live in `RightRailContainer` now — the rail
    // owns one width per mode so a panel can't animate a width of its own.

    // MARK: - UI Toggles
    var showSearch = false
    var showCaptureOverlay = false
    var inspectorUserOverride: Bool?
    var isArticleWebViewActive = false

    // MARK: - Internal State
    var nudgeEngine: NudgeEngine?
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
