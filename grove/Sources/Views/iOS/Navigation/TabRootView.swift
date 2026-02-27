import SwiftUI
import SwiftData

/// iPhone tab-based navigation with 5 tabs.
/// Each tab wraps a NavigationStack so that pushed views get their own nav bar.
/// Actual tab content views (MobileHomeView, MobileInboxView, etc.) will replace
/// the placeholder Text views as they are implemented in P3–P9.
struct TabRootView: View {
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var selectedTab: Tab = .home

    // Board suggestion state
    @State private var pendingSuggestionItemID: UUID?
    @State private var pendingSuggestion: BoardSuggestionDecision?
    @State private var showBoardSuggestion = false
    @State private var showBoardPicker = false
    @State private var suggestionDismissTask: Task<Void, Never>?

    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox }.count
    }

    enum Tab: String, Hashable {
        case home, inbox, library, chat, more
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MobileHomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(Tab.home)

            NavigationStack {
                MobileInboxView()
            }
            .tabItem {
                Label("Inbox", systemImage: "tray")
            }
            .tag(Tab.inbox)
            .badge(inboxCount)

            NavigationStack {
                MobileLibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical")
            }
            .tag(Tab.library)

            NavigationStack {
                MobileConversationListView()
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(Tab.chat)

            NavigationStack {
                MobileSettingsView()
            }
            .tabItem {
                Label("More", systemImage: "ellipsis")
            }
            .tag(Tab.more)
        }
        // Hidden buttons for iPad keyboard shortcuts (Cmd+1–5)
        .background {
            VStack {
                Button("") { selectedTab = .home }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selectedTab = .inbox }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selectedTab = .library }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { selectedTab = .chat }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { selectedTab = .more }
                    .keyboardShortcut("5", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            // Show floating capture button on content tabs (not Chat or More)
            if [Tab.home, .inbox, .library].contains(selectedTab) {
                FloatingCaptureButton()
                    .padding(.trailing, Spacing.lg)
                    .padding(.bottom, Spacing.xl)
            }
        }
        // Board suggestion banner — slides in from top after auto-tagging
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
        .onChange(of: showBoardPicker) { _, isPresented in
            if !isPresented, showBoardSuggestion {
                scheduleAutoDismiss()
            }
        }
        .onChange(of: deepLinkRouter.selectedTab) { _, newTab in
            if let newTab {
                selectedTab = newTab
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
