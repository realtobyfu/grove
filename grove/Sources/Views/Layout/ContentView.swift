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
    @State private var showNewNoteSheet = false
    @State private var showSearch = false
    @State private var showCaptureOverlay = false
    @State private var nudgeEngine: NudgeEngine?
    @State private var showBoardExportSheet = false
    @State private var showItemExportSheet = false
    @State private var showChatPanel = false
    @State private var selectedConversation: Conversation?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var savedColumnVisibility: NavigationSplitViewVisibility?
    @State private var savedInspectorOverride: Bool?
    @State private var savedChatPanel: Bool?
    @State private var chatPanelWidth: CGFloat = 380

    private var isInspectorVisible: Bool {
        if let override = inspectorUserOverride {
            return override
        }
        return selectedItem != nil
    }

    var syncService: SyncService

    /// The current board ID for the capture bar
    private var currentBoardID: UUID? {
        if case .board(let boardID) = selection {
            return boardID
        }
        return nil
    }

    /// The board scope for search — set when searching within a board context
    private var searchScopeBoard: Board? {
        if case .board(let boardID) = selection {
            return boards.first(where: { $0.id == boardID })
        }
        return nil
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
        } detail: {
            detailZStack
        }
        .frame(minWidth: 1200, minHeight: 800)
        .modifier(ContentViewEventHandlers(
            selection: $selection,
            selectedItem: $selectedItem,
            openedItem: $openedItem,
            showNewNoteSheet: $showNewNoteSheet,
            showSearch: $showSearch,
            showCaptureOverlay: $showCaptureOverlay,
            showBoardExportSheet: $showBoardExportSheet,
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
    }

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

            rightPanel
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if openedItem != nil {
                    Button {
                        openedItem = nil
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .help("Back to list")
                } else {
                    Button {
                        withAnimation {
                            if columnVisibility == .detailOnly {
                                columnVisibility = .automatic
                            } else {
                                columnVisibility = .detailOnly
                            }
                        }
                    } label: {
                        Image(systemName: "sidebar.leading")
                    }
                    .help("Toggle Sidebar")
                }
            }
            ToolbarItem(placement: .status) {
                SyncStatusView(syncService: syncService)
            }
            ToolbarItem(placement: .primaryAction) {
                chatToolbarButton
            }
            ToolbarItem(placement: .primaryAction) {
                inspectorToolbarButton
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
    }

    private var chatToolbarButton: some View {
        Button {
            withAnimation {
                showChatPanel.toggle()
            }
        } label: {
            Image(systemName: showChatPanel ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
        }
        .help(showChatPanel ? "Hide Chat" : "Show Chat")
    }

    private var inspectorToolbarButton: some View {
        Button {
            withAnimation {
                inspectorUserOverride = !isInspectorVisible
            }
        } label: {
            Image(systemName: "sidebar.trailing")
        }
        .help(isInspectorVisible ? "Hide Inspector" : "Show Inspector")
    }

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

    @ViewBuilder
    private var rightPanel: some View {
        if showChatPanel {
            // Draggable divider for chat panel
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
                                        let windowWidth = window.frame.width
                                        let newWidth = windowWidth - value.location.x
                                        chatPanelWidth = min(max(newWidth, 300), windowWidth * 0.6)
                                    }
                                }
                        )
                }
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
            Divider()
            if let selectedItem {
                InspectorPanelView(item: selectedItem)
                    .frame(width: 280)
                    .transition(.move(edge: .trailing))
            } else {
                InspectorEmptyView()
                    .frame(width: 280)
                    .transition(.move(edge: .trailing))
            }
        }
    }

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
                    PlaceholderView(
                        icon: "square.grid.2x2",
                        title: "Board",
                        message: "Board not found."
                    )
                }
            case .graph:
                GraphVisualizationView(selectedItem: $selectedItem)
            case .course(let courseID):
                if let course = courses.first(where: { $0.id == courseID }) {
                    CourseDetailView(course: course, selectedItem: $selectedItem, openedItem: $openedItem)
                } else {
                    PlaceholderView(
                        icon: "graduationcap",
                        title: "Course",
                        message: "Course not found."
                    )
                }
            case nil:
                PlaceholderView(
                    icon: "leaf",
                    title: "Grove",
                    message: "Select an item from the sidebar to get started."
                )
            }
        }
    }
}

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

struct InspectorPanelView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var allBoards: [Board]
    @Query private var allItems: [Item]
    @State private var isAddingConnection = false
    @State private var connectionSearchText = ""
    @State private var selectedConnectionType: ConnectionType = .related

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                metadataSection
                    .padding(.top)
                Divider().padding(.horizontal)
                boardMembershipSection
                Divider().padding(.horizontal)
                connectionsSection
                Divider().padding(.horizontal)
                resurfacingSection

                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.bgInspector)
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Type
            HStack {
                Image(systemName: item.type.iconName)
                    .foregroundStyle(Color.textSecondary)
                Text(item.type.rawValue.capitalized)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal)

            // Editable Title
            TextField("Title", text: $item.title)
                .textFieldStyle(.plain)
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal)
                .onChange(of: item.title) {
                    item.updatedAt = .now
                }

            // Source URL
            if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                    Text(sourceURL)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal)
            }

            // Dates
            VStack(alignment: .leading, spacing: 4) {
                Label("Created: \(item.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
                Label("Updated: \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar.badge.clock")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Board Membership Section

    private var boardMembershipSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Boards")
                .sectionHeaderStyle()
                .padding(.horizontal)

            if item.boards.isEmpty {
                Text("Not in any board")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal)
            } else {
                ForEach(item.boards) { board in
                    HStack(spacing: 6) {
                        if let icon = board.icon {
                            Image(systemName: icon)
                                .font(.groveBadge)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Text(board.title)
                            .font(.groveBody)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Connections Section

    private var connectionSearchResults: [Item] {
        let existingIDs = Set(
            item.outgoingConnections.compactMap(\.targetItem?.id) +
            item.incomingConnections.compactMap(\.sourceItem?.id)
        )
        return allItems.filter { candidate in
            guard candidate.id != item.id else { return false }
            guard !existingIDs.contains(candidate.id) else { return false }
            if connectionSearchText.isEmpty { return true }
            return candidate.title.localizedCaseInsensitiveContains(connectionSearchText)
        }.prefix(12).map { $0 }
    }

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Connections")
                    .sectionHeaderStyle()
                Spacer()
                Button {
                    isAddingConnection.toggle()
                    connectionSearchText = ""
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.groveMeta)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal)

            let allConnections = item.outgoingConnections + item.incomingConnections
            if allConnections.isEmpty && !isAddingConnection {
                Text("No connections yet")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal)
            } else {
                ForEach(allConnections) { connection in
                    connectionRow(connection)
                }
            }

            if isAddingConnection {
                addConnectionPanel
            }
        }
    }

    private var addConnectionPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Connection type picker
            Picker("Type", selection: $selectedConnectionType) {
                ForEach(ConnectionType.allCases, id: \.self) { type in
                    Text(type.displayLabel).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            // Search field
            TextField("Search items...", text: $connectionSearchText)
                .textFieldStyle(.roundedBorder)
                .font(.groveBodySmall)

            // Results
            if !connectionSearchResults.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(connectionSearchResults) { candidate in
                            Button {
                                createConnectionTo(candidate)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: candidate.type.iconName)
                                        .font(.groveBadge)
                                        .foregroundStyle(Color.textSecondary)
                                        .frame(width: 14)
                                    Text(candidate.title)
                                        .font(.groveBodySmall)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                )
            } else if !connectionSearchText.isEmpty {
                Text("No matching items")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textTertiary)
            }

            Button("Cancel") {
                isAddingConnection = false
                connectionSearchText = ""
            }
            .font(.groveBodySmall)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(Spacing.sm)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private func connectionRow(_ connection: Connection) -> some View {
        let isOutgoing = connection.sourceItem?.id == item.id
        let linkedItem = isOutgoing ? connection.targetItem : connection.sourceItem
        let typeLabel = connection.type.displayLabel

        return HStack(spacing: 6) {
            Image(systemName: isOutgoing ? "arrow.right.circle" : "arrow.left.circle")
                .font(.groveBadge)
                .foregroundStyle(Color.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(linkedItem?.title ?? "Unknown")
                    .font(.groveBody)
                    .lineLimit(1)
                    .foregroundStyle(Color.textPrimary)
                Text(typeLabel)
                    .font(.groveBadge)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentBadge)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Spacer()
            Button {
                deleteConnection(connection)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    private func createConnectionTo(_ target: Item) {
        let viewModel = ItemViewModel(modelContext: modelContext)
        _ = viewModel.createConnection(source: item, target: target, type: selectedConnectionType)
        isAddingConnection = false
        connectionSearchText = ""
        selectedConnectionType = .related
    }

    private func deleteConnection(_ connection: Connection) {
        let viewModel = ItemViewModel(modelContext: modelContext)
        viewModel.deleteConnection(connection)
    }

    // MARK: - Review Section

    private var resurfacingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Review")
                .sectionHeaderStyle()
                .padding(.horizontal)

            if item.isResurfacingEligible {
                Button {
                    item.isResurfacingPaused.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.isResurfacingPaused ? "circle" : "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(item.isResurfacingPaused ? Color.textTertiary : Color.textPrimary)
                        Text("Remind me to revisit")
                            .font(.groveBodySmall)
                            .foregroundStyle(item.isResurfacingPaused ? Color.textSecondary : Color.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                if !item.isResurfacingPaused {
                    if let nextDate = item.nextResurfaceDate {
                        HStack(spacing: 4) {
                            Image(systemName: item.isResurfacingOverdue ? "exclamationmark.circle" : "calendar.badge.clock")
                                .font(.groveBadge)
                                .foregroundStyle(item.isResurfacingOverdue ? Color.textPrimary : Color.textSecondary)
                            Text(item.isResurfacingOverdue ? "Due for review" : "Next review: \(nextDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.groveMeta)
                                .fontWeight(item.isResurfacingOverdue ? .semibold : .regular)
                                .foregroundStyle(item.isResurfacingOverdue ? Color.textPrimary : Color.textSecondary)
                        }
                        .padding(.horizontal)
                    }
                } else {
                    Text("Revisit reminders paused.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal)
                }
            } else {
                Text("Add notes or connections to enable review reminders.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal)
            }
        }
    }

}

// MARK: - Tag Chip View

struct TagChipView: View {
    let tag: Tag
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(tag.name)
                .font(.groveTag)
                .foregroundStyle(Color.textPrimary)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(tag.isAutoGenerated ? Color.borderTagDashed : Color.borderTag, lineWidth: 1)
        )
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Inspector Empty State

struct InspectorEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Select an item to see details.")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal)
                .padding(.top)

            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(Color.bgInspector)
    }
}

// MARK: - Content View Event Handlers

struct ContentViewEventHandlers: ViewModifier {
    @Binding var selection: SidebarItem?
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Binding var showNewNoteSheet: Bool
    @Binding var showSearch: Bool
    @Binding var showCaptureOverlay: Bool
    @Binding var showBoardExportSheet: Bool
    @Binding var showItemExportSheet: Bool
    @Binding var showChatPanel: Bool
    @Binding var selectedConversation: Conversation?
    @Binding var inspectorUserOverride: Bool?
    @Binding var nudgeEngine: NudgeEngine?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var savedColumnVisibility: NavigationSplitViewVisibility?
    @Binding var savedInspectorOverride: Bool?
    @Binding var savedChatPanel: Bool?
    let isInspectorVisible: Bool
    let searchScopeBoard: Board?
    let boards: [Board]
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            .onChange(of: selection) {
                selectedItem = nil
                openedItem = nil
                inspectorUserOverride = nil
            }
            .onChange(of: selectedItem) {
                inspectorUserOverride = nil
            }
            .sheet(isPresented: $showNewNoteSheet) {
                NewNoteSheet { title, noteContent in
                    let viewModel = ItemViewModel(modelContext: modelContext)
                    let note = viewModel.createNote(title: title)
                    note.content = noteContent
                    if case .board(let boardID) = selection,
                       let board = boards.first(where: { $0.id == boardID }) {
                        viewModel.assignToBoard(note, board: board)
                    }
                    selectedItem = note
                }
            }
            .modifier(ContentViewNotificationHandlers(
                showNewNoteSheet: $showNewNoteSheet,
                showSearch: $showSearch,
                showCaptureOverlay: $showCaptureOverlay,
                showBoardExportSheet: $showBoardExportSheet,
                showItemExportSheet: $showItemExportSheet,
                showChatPanel: $showChatPanel,
                selectedConversation: $selectedConversation,
                inspectorUserOverride: $inspectorUserOverride,
                selection: $selection,
                selectedItem: $selectedItem,
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
    }
}

struct ContentViewNotificationHandlers: ViewModifier {
    @Binding var showNewNoteSheet: Bool
    @Binding var showSearch: Bool
    @Binding var showCaptureOverlay: Bool
    @Binding var showBoardExportSheet: Bool
    @Binding var showItemExportSheet: Bool
    @Binding var showChatPanel: Bool
    @Binding var selectedConversation: Conversation?
    @Binding var inspectorUserOverride: Bool?
    @Binding var selection: SidebarItem?
    @Binding var selectedItem: Item?
    @Binding var nudgeEngine: NudgeEngine?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var savedColumnVisibility: NavigationSplitViewVisibility?
    @Binding var savedInspectorOverride: Bool?
    @Binding var savedChatPanel: Bool?
    let isInspectorVisible: Bool
    let searchScopeBoard: Board?
    let boards: [Board]
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .groveNewNote)) { _ in
                showNewNoteSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveToggleSearch)) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if !showSearch { showCaptureOverlay = false }
                    showSearch.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveToggleInspector)) { _ in
                withAnimation { inspectorUserOverride = !isInspectorVisible }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveCaptureBar)) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if !showCaptureOverlay { showSearch = false }
                    showCaptureOverlay.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveGoToHome)) { _ in
                selection = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveGoToBoard)) { notification in
                if let index = notification.object as? Int, index >= 1, index <= boards.count {
                    selection = .board(boards[index - 1].id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveExportBoard)) { _ in
                if searchScopeBoard != nil { showBoardExportSheet = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveExportItem)) { _ in
                if selectedItem != nil { showItemExportSheet = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveToggleChat)) { _ in
                withAnimation { showChatPanel.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveOpenConversation)) { notification in
                if let conversation = notification.object as? Conversation {
                    selectedConversation = conversation
                    withAnimation { showChatPanel = true }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveStartCheckIn)) { notification in
                guard let nudge = notification.object as? Nudge else { return }
                startCheckInConversation(from: nudge)
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveStartConversationWithPrompt)) { notification in
                let prompt = notification.object as? String ?? ""
                let seedIDs = notification.userInfo?["seedItemIDs"] as? [UUID] ?? []
                startConversation(withPrompt: prompt, seedItemIDs: seedIDs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveEnterFocusMode)) { _ in
                savedColumnVisibility = columnVisibility
                savedInspectorOverride = inspectorUserOverride
                savedChatPanel = showChatPanel
                withAnimation(.easeOut(duration: 0.25)) {
                    columnVisibility = .detailOnly
                    inspectorUserOverride = false
                    showChatPanel = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveExitFocusMode)) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    columnVisibility = savedColumnVisibility ?? .automatic
                    inspectorUserOverride = savedInspectorOverride
                    showChatPanel = savedChatPanel ?? false
                }
                savedColumnVisibility = nil
                savedInspectorOverride = nil
                savedChatPanel = nil
            }
            .sheet(isPresented: $showBoardExportSheet) {
                if let board = searchScopeBoard {
                    let items = board.isSmart
                        ? BoardViewModel.smartBoardItems(for: board, from: boards.flatMap(\.items))
                        : board.items
                    BoardExportSheet(board: board, items: items)
                }
            }
            .sheet(isPresented: $showItemExportSheet) {
                if let item = selectedItem {
                    ItemExportSheet(items: [item])
                }
            }
            .onAppear {
                guard nudgeEngine == nil else { return }
                let engine = NudgeEngine(modelContext: modelContext)
                engine.startSchedule()
                nudgeEngine = engine
            }
            .onDisappear {
                nudgeEngine?.stopSchedule()
                nudgeEngine = nil
            }
    }

    private func startConversation(withPrompt prompt: String, seedItemIDs: [UUID] = []) {
        var seedItems: [Item] = []
        if !seedItemIDs.isEmpty {
            let all = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
            seedItems = all.filter { seedItemIDs.contains($0.id) }
        }
        let service = DialecticsService()
        let conversation = service.startConversation(
            trigger: .userInitiated,
            seedItems: seedItems,
            board: nil,
            context: modelContext
        )

        // Pre-fill the prompt as a user message and immediately send it
        if !prompt.isEmpty {
            Task { @MainActor in
                _ = await service.sendMessage(
                    userText: prompt,
                    conversation: conversation,
                    context: modelContext
                )
            }
        }

        selectedConversation = conversation
        withAnimation { showChatPanel = true }
    }

    private func startCheckInConversation(from nudge: Nudge) {
        let trigger = nudge.checkInTrigger ?? .userInitiated
        let openingPrompt = nudge.checkInOpeningPrompt ?? ""
        let seedIDs = nudge.relatedItemIDs ?? []

        // Resolve seed items
        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        let seedItems = seedIDs.compactMap { id in
            allItems.first(where: { $0.id == id })
        }

        // Create conversation via DialecticsService
        let service = DialecticsService()
        let conversation = service.startConversation(
            trigger: trigger,
            seedItems: seedItems,
            board: nil,
            context: modelContext
        )

        // Add the opening prompt as an assistant message
        if !openingPrompt.isEmpty {
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: openingPrompt,
                position: conversation.nextPosition
            )
            assistantMsg.conversation = conversation
            conversation.messages.append(assistantMsg)
            modelContext.insert(assistantMsg)
            conversation.updatedAt = .now
            try? modelContext.save()
        }

        selectedConversation = conversation
        withAnimation { showChatPanel = true }
    }
}

