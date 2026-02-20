import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case home
    case library
    case board(UUID)
    case graph
    case course(UUID)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @State private var selection: SidebarItem? = .home
    @State private var inspectorUserOverride: Bool?
    @State private var selectedItem: Item?
    @State private var openedItem: Item?
    @State private var showWritePanel = false
    @State private var writePanelPrompt: String? = nil
    @State private var writePanelEditItem: Item? = nil
    @State private var writePanelWidth: CGFloat = 480
    @State private var showSearch = false
    @State private var showCaptureOverlay = false
    @State private var nudgeEngine: NudgeEngine?
    @State private var showItemExportSheet = false
    @State private var showChatPanel = false
    @State private var selectedConversation: Conversation?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var savedColumnVisibility: NavigationSplitViewVisibility?
    @State private var savedInspectorOverride: Bool?
    @State private var savedChatPanel: Bool?
    @State private var chatPanelWidth: CGFloat = 380
    @State private var inspectorWidth: CGFloat = 280

    private var isInspectorVisible: Bool {
        if let override = inspectorUserOverride {
            return override
        }
        return selectedItem != nil
    }

    var syncService: SyncService

    private var currentBoardID: UUID? {
        if case .board(let boardID) = selection {
            return boardID
        }
        return nil
    }

    private var searchScopeBoard: Board? {
        if case .board(let boardID) = selection {
            return boards.first(where: { $0.id == boardID })
        }
        return nil
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection, selectedConversation: $selectedConversation)
        } detail: {
            detailZStack
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .modifier(ContentViewEventHandlers(
            selection: $selection,
            selectedItem: $selectedItem,
            openedItem: $openedItem,
            showWritePanel: $showWritePanel,
            writePanelPrompt: $writePanelPrompt,
            showSearch: $showSearch,
            showCaptureOverlay: $showCaptureOverlay,
            showItemExportSheet: $showItemExportSheet,
            showChatPanel: $showChatPanel,
            selectedConversation: $selectedConversation,
            inspectorUserOverride: $inspectorUserOverride,
            nudgeEngine: $nudgeEngine,
            columnVisibility: $columnVisibility,
            savedColumnVisibility: $savedColumnVisibility,
            savedInspectorOverride: $savedInspectorOverride,
            savedChatPanel: $savedChatPanel,
            isInspectorVisible: isInspectorVisible,
            searchScopeBoard: searchScopeBoard,
            boards: boards,
            modelContext: modelContext
        ))
        .onChange(of: openedItem) {
            if let item = openedItem, item.type == .note {
                writePanelEditItem = item
                selectedItem = item
                openedItem = nil
                withAnimation(.easeOut(duration: 0.2)) {
                    showWritePanel = true
                }
            }
        }
    }

    // MARK: - Detail Layout

    private var detailZStack: some View {
        ZStack {
            mainContentArea
            searchOverlay
            captureOverlay
        }
    }

    private var mainContentArea: some View {
        HStack(spacing: 0) {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            writePanelSection

            sidePanel
        }
        .toolbar {
            if openedItem != nil {
                ToolbarItem(placement: .navigation) {
                    Button {
                        openedItem = nil
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .help("Back to list")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if openedItem != nil {
                        NotificationCenter.default.post(name: .groveOpenReflectMode, object: nil)
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            writePanelPrompt = nil
                            showWritePanel.toggle()
                        }
                    }
                } label: {
                    Image(systemName: openedItem != nil
                        ? "square.and.pencil"
                        : (showWritePanel ? "square.and.pencil.circle.fill" : "square.and.pencil"))
                }
                .help(openedItem != nil ? "Reflect on this item" : showWritePanel ? "Close Write Panel" : "Write a note")
                chatToolbarButton
                inspectorToolbarButton
            }
        }
    }

    private var chatToolbarButton: some View {
        Button {
            withAnimation { showChatPanel.toggle() }
        } label: {
            Image(systemName: showChatPanel ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
        }
        .help(showChatPanel ? "Hide Chat" : "Show Chat")
    }

    private var inspectorToolbarButton: some View {
        Button {
            withAnimation { inspectorUserOverride = !isInspectorVisible }
        } label: {
            Image(systemName: "sidebar.trailing")
        }
        .help(isInspectorVisible ? "Hide Inspector" : "Show Inspector")
    }

    // MARK: - Overlays

    @ViewBuilder
    private var searchOverlay: some View {
        if showSearch {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showSearch = false
                    }
                }

            VStack {
                SearchOverlayView(
                    isPresented: $showSearch,
                    scopeBoard: searchScopeBoard,
                    onSelectItem: { item in
                        selectedItem = item
                        openedItem = item
                    },
                    onSelectBoard: { board in
                        selection = .board(board.id)
                    },
                    onSelectTag: { _ in }
                )
                .padding(.top, 80)
                Spacer()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var captureOverlay: some View {
        if showCaptureOverlay {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showCaptureOverlay = false
                    }
                }

            VStack {
                CaptureBarOverlayView(
                    isPresented: $showCaptureOverlay,
                    currentBoardID: currentBoardID
                )
                .padding(.top, 80)
                Spacer()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
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
            }
    }

    @ViewBuilder
    private var writePanelSection: some View {
        if showWritePanel {
            draggableDivider(width: $writePanelWidth, min: 360, max: 700)
            NoteWriterPanelView(
                isPresented: $showWritePanel,
                currentBoardID: currentBoardID,
                prompt: writePanelPrompt,
                editingItem: writePanelEditItem,
                isSidePanel: true
            ) { note in
                writePanelPrompt = nil
                writePanelEditItem = nil
                selectedItem = note
            }
            .frame(width: writePanelWidth)
            .transition(.move(edge: .trailing))
            .onChange(of: showWritePanel) {
                if !showWritePanel {
                    writePanelPrompt = nil
                    writePanelEditItem = nil
                }
            }
        }
    }

    @ViewBuilder
    private var sidePanel: some View {
        if showChatPanel {
            draggableDivider(width: $chatPanelWidth, min: 300, max: .infinity)
            DialecticalChatPanel(
                selectedConversation: $selectedConversation,
                isVisible: $showChatPanel,
                currentBoard: searchScopeBoard,
                onNavigateToItem: { item in
                    selectedItem = item
                    openedItem = item
                }
            )
            .frame(width: chatPanelWidth)
            .transition(.move(edge: .trailing))
        } else if isInspectorVisible {
            draggableDivider(width: $inspectorWidth, min: 220, max: 480)
            if let selectedItem {
                InspectorPanelView(item: selectedItem)
                    .frame(width: inspectorWidth)
                    .transition(.move(edge: .trailing))
            } else {
                InspectorEmptyView()
                    .frame(width: inspectorWidth)
                    .transition(.move(edge: .trailing))
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let openedItem {
            ItemReaderView(item: openedItem)
        } else {
            switch selection {
            case .home:
                HomeView(selectedItem: $selectedItem, openedItem: $openedItem)
            case .library:
                LibraryView(selectedItem: $selectedItem, openedItem: $openedItem)
            case .board(let boardID):
                if let board = boards.first(where: { $0.id == boardID }) {
                    BoardDetailView(board: board, selectedItem: $selectedItem, openedItem: $openedItem)
                } else {
                    PlaceholderView(icon: "square.grid.2x2", title: "Board", message: "Board not found.")
                }
            case .graph:
                GraphVisualizationView(selectedItem: $selectedItem)
            case .course(let courseID):
                if let course = courses.first(where: { $0.id == courseID }) {
                    CourseDetailView(course: course, selectedItem: $selectedItem, openedItem: $openedItem)
                } else {
                    PlaceholderView(icon: "graduationcap", title: "Course", message: "Course not found.")
                }
            case nil:
                PlaceholderView(icon: "leaf", title: "Grove", message: "Select an item from the sidebar to get started.")
            }
        }
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
