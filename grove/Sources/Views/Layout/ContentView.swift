import SwiftUI
import SwiftData
#if os(macOS)
import AppKit

/// Hands back the AppKit window a SwiftUI view is hosted in. Window-level
/// notifications are broadcast for every window, so anything that reacts to
/// one needs to know which window is its own.
struct HostWindowReader: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowTrackingView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowTrackingView)?.onResolve = onResolve
    }
}

private final class WindowTrackingView: NSView {
    var onResolve: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onResolve?(window)
    }
}
#endif

/// macOS sidebar destinations. `.home` is the Today page; the case keeps its
/// name so the stored "home" value stays stable.
enum SidebarItem: Hashable, Codable {
    case home
    case newsletters
    case library
    case board(UUID)

    /// String encoding for @SceneStorage persistence.
    var sceneStorageValue: String {
        switch self {
        case .home: "home"
        case .newsletters: "newsletters"
        case .library: "library"
        case .board(let id): "board:\(id.uuidString)"
        }
    }

    /// Decode from @SceneStorage string. Returns nil for invalid values.
    /// "inbox" and "settings" were destinations once; they land on Today.
    init?(sceneStorageValue: String) {
        if sceneStorageValue == "home" { self = .home }
        else if sceneStorageValue == "inbox" { self = .home }
        else if sceneStorageValue == "newsletters" { self = .newsletters }
        else if sceneStorageValue == "library" { self = .library }
        else if sceneStorageValue == "settings" { self = .home }
        else if sceneStorageValue.hasPrefix("board:"),
                let uuid = UUID(uuidString: String(sceneStorageValue.dropFirst(6))) {
            self = .board(uuid)
        } else {
            return nil
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingService.self) private var onboarding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query private var allItemsForOnboarding: [Item]
    @Query private var allConversationsForOnboarding: [Conversation]
    @State private var viewModel = ContentViewModel()
    #if os(macOS)
    @State private var window: NSWindow? = nil
    @State private var isFullScreen = false
    #endif

    var syncService: SyncService

    /// Full screen over a reading surface means the page and nothing else: the
    /// window toolbar retires, and the panel's own strip carries the way out.
    private var hidesWindowToolbar: Bool {
        #if os(macOS)
        isFullScreen && viewModel.openedItem != nil
            && (viewModel.isArticleWebViewActive || viewModel.isPDFReaderActive)
        #else
        false
        #endif
    }

    private var currentBoardID: UUID? {
        if case .board(let boardID) = viewModel.selection {
            return boardID
        }
        return nil
    }

    private var searchScopeBoard: Board? {
        if case .board(let boardID) = viewModel.selection {
            return boards.first(where: { $0.id == boardID })
        }
        return nil
    }

    private var onboardingCaptureCompleted: Bool {
        !allItemsForOnboarding.isEmpty
    }

    private var onboardingOrganizeCompleted: Bool {
        allItemsForOnboarding.contains { !$0.boards.isEmpty }
    }

    private var onboardingChatCompleted: Bool {
        allConversationsForOnboarding.contains { conversation in
            conversation.messages.contains { $0.role == .user }
        }
    }

    var body: some View {
        @Bindable var vm = viewModel
        NavigationSplitView(columnVisibility: $vm.columnVisibility) {
            SidebarView(selection: $vm.selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
        } detail: {
            detailZStack
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        #if os(macOS)
        .background {
            HostWindowReader { resolved in
                guard resolved !== window else { return }
                window = resolved
                isFullScreen = resolved?.styleMask.contains(.fullScreen) ?? false
            }
            .frame(width: 0, height: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            guard let transitioned = note.object as? NSWindow, transitioned === window else { return }
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            guard let transitioned = note.object as? NSWindow, transitioned === window else { return }
            isFullScreen = false
        }
        #endif
        .modifier(ContentViewEventHandlers(
            viewModel: viewModel,
            searchScopeBoard: searchScopeBoard,
            boards: boards,
            modelContext: modelContext
        ))
        .onChange(of: viewModel.openedItem) {
            if let item = viewModel.openedItem, item.type == .note {
                viewModel.writePanelEditItem = item
                viewModel.selectedItem = item
                viewModel.openedItem = nil
                withAnimation(RightRailMetrics.widthChange) {
                    viewModel.showWritePanel = true
                }
            } else if let item = viewModel.openedItem, !item.reflections.isEmpty {
                // Save current panel state and collapse for reader (only when item has reflections)
                viewModel.enterFocusMode()
            } else if viewModel.openedItem == nil {
                viewModel.isArticleWebViewActive = false
                viewModel.isPDFReaderActive = false
                if viewModel.savedColumnVisibility != nil {
                    // Restore saved panel state when leaving reader
                    viewModel.exitFocusMode()
                }
            }
        }
        // Any route that brings chat forward (menu, deep link, "discuss",
        // a started conversation) takes the rail from the writer: there is
        // only ever one trailing column.
        .onChange(of: viewModel.showChatPanel) {
            if viewModel.showChatPanel { closeWritePanelForRail() }
        }
        .onChange(of: viewModel.selectedConversation) {
            if viewModel.selectedConversation != nil { closeWritePanelForRail() }
        }
        .onChange(of: viewModel.showWritePanel) {
            if !viewModel.showWritePanel {
                viewModel.writePanelPrompt = nil
                viewModel.writePanelEditItem = nil
            }
        }
        .onAppear {
            refreshOnboardingState()
        }
        .onChange(of: allItemsForOnboarding.count) {
            refreshOnboardingState()
        }
        .onChange(of: boards.count) {
            refreshOnboardingState()
        }
        .onChange(of: onboardingOrganizeCompleted) {
            refreshOnboardingState()
        }
        .onChange(of: onboardingChatCompleted) {
            refreshOnboardingState()
        }
    }

    // MARK: - Detail Layout

    private var detailZStack: some View {
        ZStack {
            mainContentArea
            searchOverlay
            captureOverlay
            onboardingOverlay
        }
    }

    private var mainContentArea: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                sidePanel(availableWidth: geo.size.width)
            }
        }
        .toolbar {
            if viewModel.openedItem != nil {
                ToolbarItem(placement: .navigation) {
                    Button {
                        viewModel.openedItem = nil
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .help("Back to list")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if viewModel.openedItem != nil {
                        NotificationCenter.default.post(name: .groveOpenReflectMode, object: nil)
                    } else {
                        viewModel.toggleWritePanel()
                    }
                } label: {
                    Image(systemName: viewModel.openedItem != nil
                        ? "square.and.pencil"
                        : (viewModel.showWritePanel ? "square.and.pencil.circle.fill" : "square.and.pencil"))
                }
                .help(viewModel.openedItem != nil ? "Reflect on this item" : viewModel.showWritePanel ? "Close Write Panel" : "Write a note")
                chatToolbarButton
                inspectorToolbarButton
            }
        }
        #if os(macOS)
        .toolbar(hidesWindowToolbar ? .hidden : .automatic, for: .windowToolbar)
        #endif
    }

    private var chatToolbarButton: some View {
        let chatShown = viewModel.rightRailMode == .dialectics
        return Button {
            viewModel.toggleChatPanel()
        } label: {
            Image(systemName: chatShown ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
        }
        .help(chatShown ? "Hide Chat" : "Show Chat")
    }

    private var inspectorToolbarButton: some View {
        Button {
            viewModel.toggleInspector()
        } label: {
            Image(systemName: "sidebar.trailing")
        }
        // Nothing to inspect means no rail at all, so the toggle has nothing
        // to show — don't offer it.
        .disabled(viewModel.inspectorItem == nil)
        .help(viewModel.rightRailMode == .inspector ? "Hide Inspector" : "Show Inspector")
    }

    // MARK: - Overlays

    @ViewBuilder
    private var searchOverlay: some View {
        if viewModel.showSearch {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.showSearch = false
                    }
                }

            VStack {
                @Bindable var vm = viewModel
                SearchOverlayView(
                    isPresented: $vm.showSearch,
                    scopeBoard: searchScopeBoard,
                    onSelectItem: { item in
                        viewModel.selectedItem = item
                        viewModel.openedItem = item
                    },
                    onSelectBoard: { board in
                        viewModel.selection = .board(board.id)
                    },
                    onSelectTag: { _ in }
                )
                .padding(.top, Spacing.md)
                Spacer()
            }
            .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var captureOverlay: some View {
        if viewModel.showCaptureOverlay {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.showCaptureOverlay = false
                    }
                }

            VStack {
                @Bindable var vm = viewModel
                CaptureBarOverlayView(
                    isPresented: $vm.showCaptureOverlay,
                    currentBoardID: currentBoardID
                )
                .padding(.top, 80)
                Spacer()
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var onboardingOverlay: some View {
        if onboarding.isPresented {
            OnboardingFlowView()
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    // MARK: - Panels

    /// Close the writer because something else is taking the rail.
    private func closeWritePanelForRail() {
        guard viewModel.showWritePanel else { return }
        withAnimation(RightRailMetrics.widthChange) {
            viewModel.showWritePanel = false
        }
    }

    private func sidePanel(availableWidth: CGFloat) -> some View {
        @Bindable var vm = viewModel
        return RightRailContainer(
            mode: viewModel.rightRailMode,
            availableWidth: availableWidth,
            onCollapse: {
                switch viewModel.rightRailMode {
                case .writing: viewModel.showWritePanel = false
                case .dialectics: viewModel.showChatPanel = false
                default: viewModel.inspectorUserOverride = false
                }
            }
        ) { mode in
            switch mode {
            case .writing:
                NoteWriterPanelView(
                    isPresented: $vm.showWritePanel,
                    currentBoardID: currentBoardID,
                    prompt: viewModel.writePanelPrompt,
                    editingItem: viewModel.writePanelEditItem,
                    isSidePanel: true
                ) { note in
                    viewModel.writePanelPrompt = nil
                    viewModel.writePanelEditItem = nil
                    viewModel.selectedItem = note
                }
                // A different note or prompt is a different writing session:
                // rebuild the editor so it picks up the new content.
                .id(WriteSessionKey(editItemID: viewModel.writePanelEditItem?.id, prompt: viewModel.writePanelPrompt))
            case .dialectics:
                DialecticalChatPanel(
                    selectedConversation: $vm.selectedConversation,
                    isVisible: $vm.showChatPanel,
                    currentBoard: searchScopeBoard,
                    onNavigateToItem: { item in
                        viewModel.selectedItem = item
                        viewModel.openedItem = item
                    }
                )
            case .inspector:
                if let inspectorItem = viewModel.inspectorItem {
                    InspectorPanelView(item: inspectorItem, onNavigateToItem: { target in
                        viewModel.selectedItem = target
                        viewModel.openedItem = target
                    })
                }
            default:
                EmptyView()
            }
        }
    }

    private struct WriteSessionKey: Hashable {
        let editItemID: UUID?
        let prompt: String?
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        @Bindable var vm = viewModel
        if let openedItemValue = viewModel.openedItem {
            ItemReaderView(
                item: openedItemValue,
                isWebViewActive: $vm.isArticleWebViewActive,
                isPDFSurfaceActive: $vm.isPDFReaderActive,
                railYields: viewModel.readerRailYields,
                onClaimRail: { viewModel.claimRailForReader() },
                onNavigateToItem: { item in
                    viewModel.selectedItem = item
                    viewModel.openedItem = item
                }
            )
        } else {
            switch viewModel.selection {
            case .home:
                HomeView(selectedItem: $vm.selectedItem, openedItem: $vm.openedItem)
            case .library:
                LibraryView(selectedItem: $vm.selectedItem, openedItem: $vm.openedItem)
            case .newsletters:
                NewsletterInboxView { item in
                    viewModel.selectedItem = item
                    viewModel.openedItem = item
                }
            case .board(let boardID):
                if let board = boards.first(where: { $0.id == boardID }) {
                    BoardDetailView(board: board, selectedItem: $vm.selectedItem, openedItem: $vm.openedItem)
                } else {
                    PlaceholderView(icon: "square.grid.2x2", title: "Board", message: "Board not found.")
                }
            case nil:
                PlaceholderView(icon: "leaf", title: "Grove", message: "Select an item from the sidebar to get started.")
            }
        }
    }

    private func refreshOnboardingState() {
        onboarding.updateProgress(
            captureCompleted: onboardingCaptureCompleted,
            organizeCompleted: onboardingOrganizeCompleted,
            chatCompleted: onboardingChatCompleted
        )
        onboarding.evaluateAutoPresentation(
            itemCount: allItemsForOnboarding.count,
            boardCount: boards.count
        )
    }
}

// MARK: - Placeholder View

struct PlaceholderView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text(title)
                .font(.groveItemTitle)
            Text(message)
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
