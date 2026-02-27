import SwiftUI
import SwiftData

/// Shared state for iPad reader mode. Passed via @Environment.
@Observable
final class iPadReaderCoordinator {
    var openedItem: Item?
}

/// iPad 3-column layout: Sidebar | Content | Detail
/// Matches the Mac app's NavigationSplitView structure.
/// Used when horizontalSizeClass == .regular (iPad landscape / large window).
struct iPadRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Query private var allItems: [Item]

    enum SidebarSelection: Hashable {
        case home
        case library
        case board(UUID)
        case chat
        case settings
    }

    @State private var sidebarSelection: SidebarSelection? = .home
    @State private var selectedItem: Item?
    @State private var showCaptureSheet = false
    @State private var readerCoordinator = iPadReaderCoordinator()

    // Board suggestion state (same as TabRootView)
    @State private var pendingSuggestionItemID: UUID?
    @State private var pendingSuggestion: BoardSuggestionDecision?
    @State private var showBoardSuggestion = false
    @State private var showBoardPicker = false
    @State private var suggestionDismissTask: Task<Void, Never>?

    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox }.count
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .environment(readerCoordinator)
        // Full-screen reader overlay — article left, notes right
        #if os(iOS)
        .fullScreenCover(item: Binding(
            get: { readerCoordinator.openedItem },
            set: { readerCoordinator.openedItem = $0 }
        )) { item in
            NavigationStack {
                MobileItemReaderView(item: item)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                readerCoordinator.openedItem = nil
                            } label: {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .font(.groveBody)
                                .foregroundStyle(Color.textPrimary)
                            }
                        }
                    }
            }
        }
        #endif
        // Board suggestion banner
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
        .sheet(isPresented: $showCaptureSheet) {
            CaptureSheetView()
        }
        .onChange(of: deepLinkRouter.selectedTab) { _, newTab in
            if let newTab {
                switch newTab {
                case .home: sidebarSelection = .home
                case .library: sidebarSelection = .library
                case .chat: sidebarSelection = .chat
                case .settings: sidebarSelection = .settings
                case .board(let id): sidebarSelection = .board(id)
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section {
                Label("Home", systemImage: "envelope")
                    .badge(inboxCount)
                    .tag(SidebarSelection.home)

                Label("Library", systemImage: "books.vertical")
                    .tag(SidebarSelection.library)
            }

            Section("Boards") {
                ForEach(boards) { board in
                    Label(board.title, systemImage: board.icon ?? "folder")
                        .tag(SidebarSelection.board(board.id))
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
            MobileHomeView()
        case .library:
            MobileLibraryView()
        case .board(let boardID):
            if let board = boards.first(where: { $0.id == boardID }) {
                MobileBoardDetailView(board: board)
            }
        case .chat:
            MobileConversationListView()
        case .settings:
            MobileSettingsView()
        }
    }

    // MARK: - Detail Column

    @ViewBuilder
    private var detailColumn: some View {
        if let item = selectedItem {
            ItemInspectorPanel(item: item)
        } else {
            ContentUnavailableView {
                Label("No Selection", systemImage: "sidebar.right")
            } description: {
                Text("Select an item to see its details.")
            }
        }
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
        suggestionDismissTask = Task {
            try? await Task.sleep(for: .seconds(AppConstants.Capture.boardSuggestionAutoDismissSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissBoardSuggestion()
            }
        }
    }
}
