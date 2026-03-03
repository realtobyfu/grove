import SwiftUI
import SwiftData

/// Unified iPhone/iPad navigation using iOS 18 `Tab` API.
/// iPad landscape: sidebar. iPhone & iPad portrait: tab bar.
struct TabRootView: View {
    private struct WriteSheetSession: Identifiable {
        let id = UUID()
        let boardID: UUID?
        let prompt: String?
        let editingItem: Item?
    }

    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var selectedTab: Tab = .home
    @State private var showCaptureSheet = false
    @State private var capturePrefillURL: String?
    @State private var showSearchSheet = false
    @State private var searchInitialQuery: String?
    @State private var deepLinkedConversationID: UUID?
    @State private var deepLinkedItemRoute: MobileItemRoute?
    @State private var writeSheetSession: WriteSheetSession?

    // Board suggestion state
    @State private var pendingSuggestionItemID: UUID?
    @State private var pendingSuggestion: BoardSuggestionDecision?
    @State private var showBoardSuggestion = false
    @State private var showBoardPicker = false
    @State private var suggestionDismissTask: Task<Void, Never>?

    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox }.count
    }

    private var showFloatingCapture: Bool {
        switch selectedTab {
        case .home, .library: return true
        case .board(_): return true
        default: return false
        }
    }

    private var currentBoardID: UUID? {
        guard case .board(let boardID) = selectedTab else { return nil }
        return boardID
    }

    enum Tab: Hashable {
        case home, library, chat, settings
        case board(UUID)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Main tabs

            SwiftUI.Tab("Home", systemImage: "envelope", value: Tab.home) {
                NavigationStack {
                    MobileHomeView()
                }
            }
            .badge(inboxCount)

            SwiftUI.Tab("Library", systemImage: "books.vertical", value: Tab.library) {
                NavigationStack {
                    MobileLibraryView()
                }
            }

            // MARK: - Sidebar-only: Boards

            TabSection("Boards") {
                ForEach(boards) { board in
                    SwiftUI.Tab(value: Tab.board(board.id)) {
                        NavigationStack {
                            MobileBoardDetailView(board: board)
                        }
                    } label: {
                        Label {
                            Text("\(board.title) (\(board.items.count))")
                        } icon: {
                            Image(systemName: board.icon ?? "folder")
                                .foregroundStyle(board.color.map { Color(hex: $0) } ?? Color.textSecondary)
                        }
                    }
                }
            }

            SwiftUI.Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: Tab.chat) {
                NavigationStack {
                    MobileConversationListView(initialConversationID: deepLinkedConversationID)
                }
            }

            SwiftUI.Tab("Settings", systemImage: "gearshape", value: Tab.settings) {
                NavigationStack {
                    MobileSettingsView()
                }
            }
        }
        #if os(iOS)
        .tabViewStyle(.sidebarAdaptable)
        #endif
        // Hidden buttons for iPad keyboard shortcuts (Cmd+1–4)
        .background {
            VStack {
                Button("") { selectedTab = .home }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selectedTab = .library }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selectedTab = .chat }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { selectedTab = .settings }
                    .keyboardShortcut("4", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            // Show floating capture button on content tabs (not Chat or Settings)
            if showFloatingCapture {
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
        .onReceive(NotificationCenter.default.publisher(for: .groveNewNote)) { _ in
            presentWriteSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveNewNoteWithPrompt)) { notification in
            presentWriteSheet(prompt: notification.object as? String)
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveStartConversationWithPrompt)) { notification in
            let payload = NotificationCenter.conversationPromptPayload(from: notification)
            startConversation(
                withPrompt: payload.prompt,
                seedItemIDs: payload.seedItemIDs,
                injectionMode: payload.injectionMode
            )
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
        .onAppear {
            consumeDeepLinkIntentIfNeeded()
        }
        .onChange(of: deepLinkRouter.routeVersion) { _, _ in
            consumeDeepLinkIntentIfNeeded()
        }
        .sheet(isPresented: $showCaptureSheet) {
            CaptureSheetView(prefillURL: capturePrefillURL)
        }
        .sheet(isPresented: $showSearchSheet) {
            MobileSearchView(initialQuery: searchInitialQuery)
        }
        .sheet(item: $writeSheetSession) { session in
            NoteWriterPanelView(
                isPresented: Binding(
                    get: { writeSheetSession != nil },
                    set: { isPresented in
                        if !isPresented {
                            writeSheetSession = nil
                        }
                    }
                ),
                currentBoardID: session.boardID,
                prompt: session.prompt,
                editingItem: session.editingItem
            ) { _ in
                writeSheetSession = nil
            }
        }
        .sheet(item: $deepLinkedItemRoute) { route in
            NavigationStack {
                MobileItemRouteDestinationView(route: route)
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
        suggestionDismissTask = MainActorTaskScheduler.schedule(
            after: .seconds(AppConstants.Capture.boardSuggestionAutoDismissSeconds)
        ) {
            dismissBoardSuggestion()
        }
    }

    // MARK: - Deep Links

    private func consumeDeepLinkIntentIfNeeded() {
        guard let intent = deepLinkRouter.consumeRouteIntent() else { return }

        switch intent {
        case .item(let itemID):
            selectedTab = .home
            deepLinkedItemRoute = MobileItemRoute(id: itemID)

        case .board(let boardID):
            if boards.contains(where: { $0.id == boardID }) {
                selectedTab = .board(boardID)
            } else {
                selectedTab = .library
            }

        case .chat(let conversationID):
            selectedTab = .chat
            deepLinkedConversationID = conversationID

        case .capture(let prefillURL):
            selectedTab = .home
            capturePrefillURL = prefillURL
            showCaptureSheet = true

        case .search(let query):
            selectedTab = .library
            searchInitialQuery = query
            showSearchSheet = true
        }
    }

    private func presentWriteSheet(prompt: String? = nil, editingItem: Item? = nil) {
        let trimmedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        writeSheetSession = WriteSheetSession(
            boardID: currentBoardID,
            prompt: trimmedPrompt?.isEmpty == false ? trimmedPrompt : nil,
            editingItem: editingItem
        )
    }

    private func startConversation(
        withPrompt prompt: String,
        seedItemIDs: [UUID] = [],
        injectionMode: ConversationPromptInjectionMode = .asAssistantGreeting
    ) {
        let service = DialecticsService()
        let seedItems = allItems.filter { seedItemIDs.contains($0.id) }
        let conversation = service.startConversation(
            trigger: .userInitiated,
            seedItems: seedItems,
            board: currentBoardID.flatMap { boardID in
                boards.first(where: { $0.id == boardID })
            },
            context: modelContext
        )

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            switch injectionMode {
            case .asUserMessage:
                Task { @MainActor in
                    _ = await service.sendMessage(
                        userText: trimmedPrompt,
                        conversation: conversation,
                        context: modelContext
                    )
                }
            case .asSystemPrompt:
                let systemMessage = ChatMessage(
                    role: .system,
                    content: trimmedPrompt,
                    position: conversation.nextPosition
                )
                systemMessage.conversation = conversation
                conversation.messages.append(systemMessage)
                modelContext.insert(systemMessage)
                conversation.updatedAt = .now
                try? modelContext.save()
            case .asAssistantGreeting:
                let assistantMessage = ChatMessage(
                    role: .assistant,
                    content: trimmedPrompt,
                    position: conversation.nextPosition
                )
                assistantMessage.conversation = conversation
                conversation.messages.append(assistantMessage)
                modelContext.insert(assistantMessage)
                conversation.updatedAt = .now
                try? modelContext.save()
            }
        }

        selectedTab = .chat
        deepLinkedConversationID = conversation.id
    }
}
