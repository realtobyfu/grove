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
    var chatPanelWidth: CGFloat = LayoutSettings.width(for: .contentChat) ?? 380
    var inspectorWidth: CGFloat = LayoutSettings.width(for: .contentInspector) ?? 360

    // MARK: - UI Toggles
    var showSearch = false
    var showCaptureOverlay = false
    var inspectorUserOverride: Bool?
    var showItemExportSheet = false
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

    func enterFocusMode() {
        if savedColumnVisibility == nil {
            savedColumnVisibility = columnVisibility
            savedInspectorOverride = inspectorUserOverride
            savedChatPanel = showChatPanel
        }
        withAnimation(.easeOut(duration: 0.25)) {
            columnVisibility = .detailOnly
            inspectorUserOverride = false
            showChatPanel = false
        }
    }

    func exitFocusMode() {
        withAnimation(.easeOut(duration: 0.25)) {
            columnVisibility = savedColumnVisibility ?? .automatic
            inspectorUserOverride = savedInspectorOverride
            showChatPanel = savedChatPanel ?? false
        }
        savedColumnVisibility = nil
        savedInspectorOverride = nil
        savedChatPanel = nil
    }
}
