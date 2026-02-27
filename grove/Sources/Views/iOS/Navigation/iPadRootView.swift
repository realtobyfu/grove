import SwiftUI
import SwiftData

/// Shared iPad state for split interactions.
@Observable
final class iPadReaderCoordinator {
    var openedItem: Item?
    var selectedItem: Item?
}

/// iPad 3-column layout: Sidebar | Content | Detail.
/// Mirrors the Mac app split layout semantics.
struct iPadRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Query private var allItems: [Item]

    enum SidebarSelection: Hashable {
        case home
        case inbox
        case library
        case board(UUID)
        case chat
        case settings

        var sceneStorageValue: String {
            switch self {
            case .home: "home"
            case .inbox: "inbox"
            case .library: "library"
            case .board(let id): "board:\(id.uuidString)"
            case .chat: "chat"
            case .settings: "settings"
            }
        }

        init?(sceneStorageValue: String) {
            if sceneStorageValue == "home" { self = .home }
            else if sceneStorageValue == "inbox" { self = .inbox }
            else if sceneStorageValue == "library" { self = .library }
            else if sceneStorageValue == "chat" { self = .chat }
            else if sceneStorageValue == "settings" { self = .settings }
            else if sceneStorageValue.hasPrefix("board:"),
                    let uuid = UUID(uuidString: String(sceneStorageValue.dropFirst(6))) {
                self = .board(uuid)
            } else {
                return nil
            }
        }
    }

    @State private var sidebarSelection: SidebarSelection? = .home
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var showCaptureSheet = false
    @State private var capturePrefillURL: String?
    @State private var showSearchSheet = false
    @State private var searchInitialQuery: String?
    @State private var deepLinkedConversationID: UUID?
    @State private var readerCoordinator = iPadReaderCoordinator()

    // Board suggestion state (same behavior as TabRootView).
    @State private var pendingSuggestionItemID: UUID?
    @State private var pendingSuggestion: BoardSuggestionDecision?
    @State private var showBoardSuggestion = false
    @State private var showBoardPicker = false
    @State private var showNewBoardSheet = false
    @State private var suggestionDismissTask: Task<Void, Never>?

    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox }.count
    }

    private var boardViewModel: BoardViewModel {
        BoardViewModel(modelContext: modelContext)
    }

    private var selectedItemBinding: Binding<Item?> {
        Binding(
            get: { readerCoordinator.selectedItem },
            set: { readerCoordinator.selectedItem = $0 }
        )
    }

    private var openedItemBinding: Binding<Item?> {
        Binding(
            get: { readerCoordinator.openedItem },
            set: { readerCoordinator.openedItem = $0 }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            sidebar
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .environment(readerCoordinator)
        #if os(iOS)
        .fullScreenCover(item: openedItemBinding) { item in
            NavigationStack {
                MobileItemReaderView(
                    item: item,
                    onCloseRequested: {
                        readerCoordinator.openedItem = nil
                    }
                )
            }
        }
        #endif
        .overlay(alignment: .top) {
            if showBoardSuggestion, let decision = pendingSuggestion {
                MobileBoardSuggestionBanner(
                    decision: decision,
                    onAccept: { acceptBoardSuggestion() },
                    onChoose: { showBoardPicker = true },
                    onDismiss: { dismissBoardSuggestion() }
                )
                .padding(.top, Spacing.md)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showBoardSuggestion)
        .onAppear {
            // iPad default shell: Home in 2-column mode with sidebar collapsed.
            sidebarSelection = .home
            splitViewVisibility = .doubleColumn
            consumeDeepLinkIntentIfNeeded()
        }
        .onChange(of: readerCoordinator.openedItem?.id) { _, _ in
            if let opened = readerCoordinator.openedItem {
                readerCoordinator.selectedItem = opened
            }
        }
        .onChange(of: deepLinkRouter.routeVersion) { _, _ in
            consumeDeepLinkIntentIfNeeded()
        }
        .onChange(of: deepLinkRouter.selectedTab) { _, newTab in
            guard let newTab else { return }
            switch newTab {
            case .home: sidebarSelection = .home
            case .library: sidebarSelection = .library
            case .chat: sidebarSelection = .chat
            case .settings: sidebarSelection = .settings
            case .board(let id): sidebarSelection = .board(id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveNewBoardSuggestion)) { notification in
            guard let result = BoardSuggestionMetadata.decision(from: notification) else { return }
            pendingSuggestionItemID = result.itemID
            pendingSuggestion = result.decision

            withAnimation(.easeOut(duration: 0.2)) {
                showBoardSuggestion = true
            }

            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            scheduleAutoDismiss()
        }
        .sheet(isPresented: $showBoardPicker) {
            if let suggestion = pendingSuggestion {
                SmartBoardPickerSheet(
                    boards: boards,
                    suggestedName: suggestion.suggestedName,
                    recommendedBoardID: suggestion.recommendedBoardID,
                    prioritizedBoardIDs: suggestion.alternativeBoardIDs,
                    onSelectBoard: { board in
                        assignPendingItem(to: board)
                        dismissBoardSuggestion()
                    },
                    onCreateBoard: { boardName in
                        createBoardFromPicker(named: boardName)
                        dismissBoardSuggestion()
                    }
                )
            }
        }
        .sheet(isPresented: $showNewBoardSheet) {
            BoardEditorSheet(
                onSave: { title, icon, color, nudgeFreq in
                    boardViewModel.createBoard(
                        title: title,
                        icon: icon,
                        color: color,
                        nudgeFrequencyHours: nudgeFreq
                    )
                }
            )
        }
        .sheet(isPresented: $showCaptureSheet) {
            CaptureSheetView(prefillURL: capturePrefillURL)
        }
        .sheet(isPresented: $showSearchSheet) {
            MobileSearchView(initialQuery: searchInitialQuery)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section {
                Label("Home", systemImage: "envelope")
                    .badge(inboxCount)
                    .tag(SidebarSelection.home)

                Label("Inbox", systemImage: "tray")
                    .badge(inboxCount)
                    .tag(SidebarSelection.inbox)

                Label("Library", systemImage: "books.vertical")
                    .tag(SidebarSelection.library)
            }

            Section {
                ForEach(boards) { board in
                    Label(board.title, systemImage: board.icon ?? "folder")
                        #if os(iOS)
                        .padding(.leading, Spacing.md)
                        #endif
                        .tag(SidebarSelection.board(board.id))
                }
            } header: {
                HStack(spacing: Spacing.sm) {
                    Text("Boards")
                        .sectionHeaderStyle()

                    Spacer()

                    Button {
                        showNewBoardSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New board")
                    .accessibilityHint("Create a board in the sidebar list.")
                }
                .contextMenu {
                    Button("New Board...") {
                        showNewBoardSheet = true
                    }
                }
            }

            Section {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    .tag(SidebarSelection.chat)
            }

            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarSelection.settings)
            }
        }
        .navigationTitle("Grove")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    capturePrefillURL = nil
                    showCaptureSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Capture")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    // MARK: - Content Column

    @ViewBuilder
    private var contentColumn: some View {
        switch sidebarSelection {
        case .home, .none:
            MobileHomeView(
                selectedItem: selectedItemBinding,
                openedItem: openedItemBinding
            )
        case .inbox:
            MobileInboxView(
                selectedItem: selectedItemBinding,
                openedItem: openedItemBinding
            )
        case .library:
            MobileLibraryView(
                selectedItem: selectedItemBinding,
                openedItem: openedItemBinding
            )
        case .board(let boardID):
            if let board = boards.first(where: { $0.id == boardID }) {
                MobileBoardDetailView(
                    board: board,
                    selectedItem: selectedItemBinding,
                    openedItem: openedItemBinding
                )
            } else {
                ContentUnavailableView("Board not found", systemImage: "folder")
            }
        case .chat:
            MobileConversationListView(initialConversationID: deepLinkedConversationID)
        case .settings:
            MobileSettingsView()
        }
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        if let item = readerCoordinator.selectedItem ?? readerCoordinator.openedItem {
            ItemInspectorPanel(item: item)
        } else {
            ContentUnavailableView {
                Label("No Selection", systemImage: "sidebar.right")
            } description: {
                Text("Select an item to see its details.")
            }
        }
    }

    // MARK: - Deep Links

    private func consumeDeepLinkIntentIfNeeded() {
        guard let intent = deepLinkRouter.consumeRouteIntent() else { return }

        switch intent {
        case .item(let itemID):
            guard let item = fetchItem(id: itemID) else { return }
            readerCoordinator.selectedItem = item
            readerCoordinator.openedItem = item
            sidebarSelection = .home

        case .board(let boardID):
            sidebarSelection = .board(boardID)
            readerCoordinator.openedItem = nil

        case .chat(let conversationID):
            sidebarSelection = .chat
            deepLinkedConversationID = conversationID
            readerCoordinator.openedItem = nil

        case .capture(let prefillURL):
            capturePrefillURL = prefillURL
            showCaptureSheet = true

        case .search(let query):
            searchInitialQuery = query
            showSearchSheet = true
        }
    }

    private func fetchItem(id: UUID) -> Item? {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Board Suggestion Actions

    private func acceptBoardSuggestion() {
        guard let suggestion = pendingSuggestion else {
            dismissBoardSuggestion()
            return
        }

        let suggestedName = BoardSuggestionEngine.cleanedBoardName(suggestion.suggestedName)

        let board: Board
        if suggestion.mode == .existing,
           let recommendedBoardID = suggestion.recommendedBoardID,
           let recommended = boards.first(where: { $0.id == recommendedBoardID }) {
            board = recommended
        } else if let existing = boards.first(where: {
            $0.title.localizedCaseInsensitiveCompare(suggestedName) == .orderedSame
        }) {
            board = existing
        } else {
            let newBoard = Board(title: suggestedName.isEmpty ? "General" : suggestedName)
            modelContext.insert(newBoard)
            board = newBoard
        }

        assignPendingItem(to: board)
        dismissBoardSuggestion()
    }

    private func createBoardFromPicker(named boardName: String) {
        let normalizedName = BoardSuggestionEngine.cleanedBoardName(boardName)
        guard !normalizedName.isEmpty else { return }

        if let existing = boards.first(where: {
            $0.title.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
        }) {
            assignPendingItem(to: existing)
        } else {
            let newBoard = Board(title: normalizedName)
            modelContext.insert(newBoard)
            assignPendingItem(to: newBoard)
        }
    }

    private func assignPendingItem(to board: Board) {
        guard let itemID = pendingSuggestionItemID else { return }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? modelContext.fetch(descriptor).first else { return }

        if !item.boards.contains(where: { $0.id == board.id }) {
            item.boards.append(board)
        }

        BoardSuggestionMetadata.clearPendingSuggestion(on: item)
        try? modelContext.save()
    }

    private func dismissBoardSuggestion() {
        suggestionDismissTask?.cancel()
        suggestionDismissTask = nil
        showBoardPicker = false

        withAnimation(.easeOut(duration: 0.2)) {
            showBoardSuggestion = false
        }

        pendingSuggestionItemID = nil
        pendingSuggestion = nil
    }

    private func scheduleAutoDismiss() {
        suggestionDismissTask?.cancel()
        suggestionDismissTask = MainActorTaskScheduler.schedule(
            after: .seconds(AppConstants.Capture.boardSuggestionAutoDismissSeconds)
        ) {
            dismissBoardSuggestion()
        }
    }
}
