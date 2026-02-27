import SwiftUI
import SwiftData

enum SidebarItem: Hashable, Codable {
    case home
    case inbox
    case library
    case board(UUID)
    case graph
    case course(UUID)
    case settings

    /// String encoding for @SceneStorage persistence.
    var sceneStorageValue: String {
        switch self {
        case .home: "home"
        case .inbox: "inbox"
        case .library: "library"
        case .board(let id): "board:\(id.uuidString)"
        case .graph: "graph"
        case .course(let id): "course:\(id.uuidString)"
        case .settings: "settings"
        }
    }

    /// Decode from @SceneStorage string. Returns nil for invalid values.
    init?(sceneStorageValue: String) {
        if sceneStorageValue == "home" { self = .home }
        else if sceneStorageValue == "inbox" { self = .inbox }
        else if sceneStorageValue == "library" { self = .library }
        else if sceneStorageValue == "graph" { self = .graph }
        else if sceneStorageValue == "settings" { self = .settings }
        else if sceneStorageValue.hasPrefix("board:"),
                let uuid = UUID(uuidString: String(sceneStorageValue.dropFirst(6))) {
            self = .board(uuid)
        } else if sceneStorageValue.hasPrefix("course:"),
                  let uuid = UUID(uuidString: String(sceneStorageValue.dropFirst(7))) {
            self = .course(uuid)
        } else {
            return nil
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(OnboardingService.self) private var onboarding
    @State private var coachMarks = CoachMarkService.shared
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @Query private var allItemsForOnboarding: [Item]
    @Query private var allConversationsForOnboarding: [Conversation]
    @State private var viewModel = ContentViewModel()

    var syncService: SyncService

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
            SidebarView(selection: $vm.selection, selectedConversation: $vm.selectedConversation)
        } detail: {
            detailZStack
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
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
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.showWritePanel = true
                }
            } else if let item = viewModel.openedItem, !item.reflections.isEmpty {
                // Save current panel state and collapse for reader (only when item has reflections)
                viewModel.enterFocusMode()
            } else if viewModel.openedItem == nil {
                viewModel.isArticleWebViewActive = false
                if viewModel.savedColumnVisibility != nil {
                    // Restore saved panel state when leaving reader
                    viewModel.exitFocusMode()
                }
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
            coachMarkOverlay
        }
    }

    private var mainContentArea: some View {
        @Bindable var vm = viewModel
        return HStack(spacing: 0) {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if viewModel.isInspectorVisible && viewModel.selectedItem != nil && viewModel.openedItem == nil {
                        Color.black.opacity(0.04)
                            .allowsHitTesting(false)
                    }
                }

            writePanelSection

            sidePanel
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
                        withAnimation(.easeOut(duration: 0.2)) {
                            viewModel.writePanelPrompt = nil
                            viewModel.showWritePanel.toggle()
                        }
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
    }

    private var chatToolbarButton: some View {
        Button {
            withAnimation { viewModel.showChatPanel.toggle() }
        } label: {
            Image(systemName: viewModel.showChatPanel ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
        }
        .help(viewModel.showChatPanel ? "Hide Chat" : "Show Chat")
    }

    private var inspectorToolbarButton: some View {
        Button {
            withAnimation { viewModel.inspectorUserOverride = !viewModel.isInspectorVisible }
        } label: {
            Image(systemName: "sidebar.trailing")
        }
        .help(viewModel.isInspectorVisible ? "Hide Inspector" : "Show Inspector")
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
                .padding(.top, 12)
                Spacer()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
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
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var onboardingOverlay: some View {
        if onboarding.isPresented {
            OnboardingFlowView()
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var coachMarkOverlay: some View {
        @Bindable var vm = viewModel
        CoachMarkOverlay(
            coachMarks: coachMarks,
            showChatPanel: $vm.showChatPanel
        )
    }

    // MARK: - Panels

    private func draggableDivider(width: Binding<CGFloat>, min minWidth: CGFloat, max maxWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.borderPrimary)
            .frame(width: 1)
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    #if os(macOS)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                if let window = NSApp.keyWindow {
                                    let newWidth = window.frame.width - value.location.x
                                    width.wrappedValue = Swift.min(Swift.max(newWidth, minWidth), maxWidth)
                                }
                            }
                    )
                    #endif
            }
    }

    @ViewBuilder
    private var writePanelSection: some View {
        if viewModel.showWritePanel {
            @Bindable var vm = viewModel
            draggableDivider(width: $vm.writePanelWidth, min: 360, max: 700)
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
            .frame(width: viewModel.writePanelWidth)
            .transition(.move(edge: .trailing))
            .onChange(of: viewModel.showWritePanel) {
                if !viewModel.showWritePanel {
                    viewModel.writePanelPrompt = nil
                    viewModel.writePanelEditItem = nil
                }
            }
        }
    }

    @ViewBuilder
    private var sidePanel: some View {
        if viewModel.showChatPanel {
            @Bindable var vm = viewModel
            draggableDivider(width: $vm.chatPanelWidth, min: 300, max: .infinity)
            DialecticalChatPanel(
                selectedConversation: $vm.selectedConversation,
                isVisible: $vm.showChatPanel,
                currentBoard: searchScopeBoard,
                onNavigateToItem: { item in
                    viewModel.selectedItem = item
                    viewModel.openedItem = item
                }
            )
            .frame(width: viewModel.chatPanelWidth)
            .transition(.move(edge: .trailing))
        } else if viewModel.isInspectorVisible {
            @Bindable var vm = viewModel
            draggableDivider(width: $vm.inspectorWidth, min: 300, max: 520)
            if let inspectorItem = viewModel.selectedItem ?? viewModel.openedItem {
                InspectorPanelView(item: inspectorItem)
                    .frame(width: viewModel.inspectorWidth)
                    .transition(.move(edge: .trailing))
            } else {
                InspectorEmptyView()
                    .frame(width: viewModel.inspectorWidth)
                    .transition(.move(edge: .trailing))
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        @Bindable var vm = viewModel
        if let openedItemValue = viewModel.openedItem {
            ItemReaderView(item: openedItemValue, isWebViewActive: $vm.isArticleWebViewActive, onNavigateToItem: { item in
                viewModel.selectedItem = item
                viewModel.openedItem = item
            })
        } else {
            switch viewModel.selection {
            case .home:
                HomeView(selectedItem: $vm.selectedItem, openedItem: $vm.openedItem)
            case .library:
                LibraryView(selectedItem: $vm.selectedItem, openedItem: $vm.openedItem)
            case .board(let boardID):
                if let board = boards.first(where: { $0.id == boardID }) {
                    BoardDetailView(board: board, selectedItem: $vm.selectedItem, openedItem: $vm.openedItem)
                } else {
                    PlaceholderView(icon: "square.grid.2x2", title: "Board", message: "Board not found.")
                }
            case .graph:
                GraphVisualizationView(selectedItem: $vm.selectedItem, openedItem: $vm.openedItem)
            case .course(let courseID):
                if let course = courses.first(where: { $0.id == courseID }) {
                    CourseDetailView(course: course, selectedItem: $vm.selectedItem, openedItem: $vm.openedItem)
                } else {
                    PlaceholderView(icon: "graduationcap", title: "Course", message: "Course not found.")
                }
            case .inbox, .settings:
                // iPad-only sidebar items; unused on macOS
                PlaceholderView(icon: "leaf", title: "Grove", message: "Select an item from the sidebar to get started.")
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
