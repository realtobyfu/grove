import SwiftUI
import SwiftData

/// Shared iPad selection state for views that can either highlight or open items.
@Observable
final class iPadReaderCoordinator {
    var openedItem: Item?
    var selectedItem: Item?
}

/// iPad layout: sidebar navigation on the left and a single stacked workspace on the right.
struct iPadRootView: View {
    private struct WriteSheetSession: Identifiable {
        let id = UUID()
        let boardID: UUID?
        let prompt: String?
        let editingItem: Item?
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query private var allItems: [Item]

    private enum DetailRoute: Hashable {
        case item(UUID)
    }

    enum SidebarSelection: Hashable {
        case home
        case library
        case board(UUID)
        case chat
        case settings

        var sceneStorageValue: String {
            switch self {
            case .home: "home"
            case .library: "library"
            case .board(let id): "board:\(id.uuidString)"
            case .chat: "chat"
            case .settings: "settings"
            }
        }

        init?(sceneStorageValue: String) {
            if sceneStorageValue == "home" { self = .home }
            else if sceneStorageValue == "inbox" { self = .home }
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
    @State private var detailPath = NavigationPath()
    @State private var pendingDetailRoute: DetailRoute?
    @State private var writeSheetSession: WriteSheetSession?

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

    private var currentBoardID: UUID? {
        guard case .board(let boardID) = sidebarSelection else { return nil }
        return boardID
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
        } detail: {
            NavigationStack(path: $detailPath) {
                primaryContent
            }
            .environment(readerCoordinator)
            .navigationDestination(for: DetailRoute.self) { route in
                detailDestination(for: route)
            }
        }
        .navigationSplitViewStyle(.balanced)
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
            sidebarSelection = .home
            splitViewVisibility = .doubleColumn
            consumeDeepLinkIntentIfNeeded()
        }
        .onChange(of: sidebarSelection?.sceneStorageValue) { _, _ in
            detailPath = NavigationPath()
            readerCoordinator.selectedItem = nil
            readerCoordinator.openedItem = nil

            guard let pendingDetailRoute else { return }
            detailPath.append(pendingDetailRoute)
            self.pendingDetailRoute = nil
        }
        .onChange(of: readerCoordinator.openedItem?.id) { _, _ in
            guard let item = readerCoordinator.openedItem else { return }
            readerCoordinator.selectedItem = item
            readerCoordinator.openedItem = nil
            if item.type == .note {
                presentWriteSheet(editingItem: item)
            } else {
                showItemReader(for: item)
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
            ) { note in
                readerCoordinator.selectedItem = note
                writeSheetSession = nil
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

    // MARK: - Primary Content

    @ViewBuilder
    private var primaryContent: some View {
        switch sidebarSelection {
        case .home, .none:
            MobileHomeView(onOpenItem: { item in
                openItemInPreferredContext(item)
            })
        case .library:
            MobileLibraryView(onOpenItem: { item in
                openItemInPreferredContext(item)
            })
        case .board(let boardID):
            if let board = boards.first(where: { $0.id == boardID }) {
                MobileBoardDetailView(
                    board: board,
                    onOpenItem: { item in
                        openItemInPreferredContext(item)
                    },
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

    @ViewBuilder
    private func detailDestination(for route: DetailRoute) -> some View {
        switch route {
        case .item(let itemID):
            if let item = fetchItem(id: itemID) {
                MobileItemReaderView(item: item)
            } else {
                ContentUnavailableView("Item not found", systemImage: "doc.text")
            }
        }
    }

    // MARK: - Deep Links

    private func consumeDeepLinkIntentIfNeeded() {
        guard let intent = deepLinkRouter.consumeRouteIntent() else { return }

        switch intent {
        case .item(let itemID):
            guard let item = fetchItem(id: itemID) else { return }
            openItemInPreferredContext(item)

        case .board(let boardID):
            sidebarSelection = .board(boardID)

        case .chat(let conversationID):
            sidebarSelection = .chat
            deepLinkedConversationID = conversationID

        case .capture(let prefillURL):
            capturePrefillURL = prefillURL
            showCaptureSheet = true

        case .search(let query):
            sidebarSelection = .library
            searchInitialQuery = query
            showSearchSheet = true
        }
    }

    private func openItemInPreferredContext(_ item: Item) {
        readerCoordinator.selectedItem = item

        if item.type == .note {
            presentWriteSheet(editingItem: item)
            return
        }

        let destinationSelection = detailHostingSelection(for: item)
        if sidebarSelection == destinationSelection {
            showItemReader(for: item)
        } else {
            pendingDetailRoute = .item(item.id)
            sidebarSelection = destinationSelection
        }
    }

    private func preferredSidebarSelection(for item: Item) -> SidebarSelection {
        if let board = boards.first(where: { board in
            item.boards.contains(where: { $0.id == board.id })
        }) {
            return .board(board.id)
        }

        return .library
    }

    private func detailHostingSelection(for item: Item) -> SidebarSelection {
        switch sidebarSelection {
        case .home?, .library?:
            return sidebarSelection ?? preferredSidebarSelection(for: item)
        case .board(let boardID)? where item.boards.contains(where: { $0.id == boardID }):
            return .board(boardID)
        default:
            return preferredSidebarSelection(for: item)
        }
    }

    private func showItemReader(for item: Item) {
        detailPath = NavigationPath()
        detailPath.append(DetailRoute.item(item.id))
    }

    private func presentWriteSheet(prompt: String? = nil, editingItem: Item? = nil) {
        let trimmedPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        detailPath = NavigationPath()
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

        detailPath = NavigationPath()
        sidebarSelection = .chat
        deepLinkedConversationID = conversation.id
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
