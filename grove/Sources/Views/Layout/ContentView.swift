import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case inbox
    case board(UUID)
    case tags
    case graph
    case course(UUID)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @State private var selection: SidebarItem? = .inbox
    @State private var showInspector = true
    @State private var selectedItem: Item?
    @State private var openedItem: Item?
    @State private var showNewNoteSheet = false
    @State private var showSearch = false
    @State private var nudgeEngine: NudgeEngine?
    @State private var showBoardExportSheet = false
    @State private var showItemExportSheet = false

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
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            ZStack {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        NudgeBarView(
                            onOpenItem: { item in
                                selectedItem = item
                                openedItem = item
                            },
                            onTriageInbox: {
                                selection = .inbox
                            },
                            resurfacingService: nudgeEngine?.resurfacingService
                        )

                        CaptureBarView(currentBoardID: currentBoardID)

                        detailContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if showInspector {
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
                .toolbar {
                    ToolbarItem(placement: .status) {
                        SyncStatusView(syncService: syncService)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation {
                                showInspector.toggle()
                            }
                        } label: {
                            Image(systemName: "sidebar.trailing")
                        }
                        .help(showInspector ? "Hide Inspector (⌘])" : "Show Inspector (⌘])")
                    }
                }

                // Search overlay
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
                            onSelectTag: { _ in
                                selection = .tags
                            }
                        )
                        .padding(.top, 80)
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .frame(minWidth: 1200, minHeight: 800)
        .onChange(of: selection) {
            selectedItem = nil
            openedItem = nil
        }
        .sheet(isPresented: $showNewNoteSheet) {
            NewNoteSheet { title, content in
                let viewModel = ItemViewModel(modelContext: modelContext)
                let note = viewModel.createNote(title: title)
                note.content = content
                // If a board is selected, assign to it
                if case .board(let boardID) = selection,
                   let board = boards.first(where: { $0.id == boardID }) {
                    viewModel.assignToBoard(note, board: board)
                }
                selectedItem = note
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveNewNote)) { _ in
            showNewNoteSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveToggleSearch)) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                showSearch.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveToggleInspector)) { _ in
            withAnimation {
                showInspector.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveGoToInbox)) { _ in
            selection = .inbox
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveGoToBoard)) { notification in
            if let index = notification.object as? Int, index >= 1, index <= boards.count {
                selection = .board(boards[index - 1].id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveGoToTags)) { _ in
            selection = .tags
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveExportBoard)) { _ in
            if searchScopeBoard != nil {
                showBoardExportSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveExportItem)) { _ in
            if selectedItem != nil {
                showItemExportSheet = true
            }
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

    @ViewBuilder
    private var detailContent: some View {
        if let openedItem {
            ItemReaderView(item: openedItem)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            self.openedItem = nil
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .help("Back to list")
                    }
                }
        } else {
            switch selection {
            case .inbox:
                InboxTriageView(selectedItem: $selectedItem, openedItem: $openedItem)
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
            case .tags:
                TagBrowserView(selectedItem: $selectedItem)
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
    @Query private var allTags: [Tag]
    @Query(sort: \Board.sortOrder) private var allBoards: [Board]
    @Query private var allItems: [Item]
    @State private var tagSearchText = ""
    @State private var isAddingTag = false
    @State private var newTagCategory: TagCategory = .custom
    @State private var isAddingConnection = false
    @State private var connectionSearchText = ""
    @State private var selectedConnectionType: ConnectionType = .related

    private var filteredTags: [Tag] {
        let existingIDs = Set(item.tags.map(\.id))
        let available = allTags.filter { !existingIDs.contains($0.id) }
        if tagSearchText.isEmpty { return available }
        return available.filter {
            $0.name.localizedCaseInsensitiveContains(tagSearchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Inspector")
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal)
                    .padding(.top)

                metadataSection
                Divider().padding(.horizontal)
                tagSection
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

    // MARK: - Tag Section

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Tags")
                    .sectionHeaderStyle()
                Spacer()
                Button {
                    isAddingTag.toggle()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.groveMeta)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal)

            // Current tags
            if !item.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(item.tags) { tag in
                        TagChipView(tag: tag) {
                            removeTag(tag)
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Add tag with autocomplete
            if isAddingTag {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        TextField("Search or create tag...", text: $tagSearchText)
                            .textFieldStyle(.roundedBorder)
                            .font(.groveBodySmall)
                            .onSubmit {
                                createAndAddTag()
                            }
                        Picker("", selection: $newTagCategory) {
                            ForEach(TagCategory.allCases, id: \.self) { cat in
                                Text(cat.displayName).tag(cat)
                            }
                        }
                        .font(.groveBadge)
                        .frame(width: 90)
                    }

                    if !filteredTags.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(filteredTags.prefix(8)) { tag in
                                    Button {
                                        addTag(tag)
                                    } label: {
                                        HStack {
                                            Text(tag.name)
                                                .font(.groveTag)
                                            Spacer()
                                            Text(tag.category.displayName)
                                                .font(.groveBadge)
                                                .foregroundStyle(Color.textTertiary)
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
                    }

                    // Hint: press Enter to create if no match
                    if !tagSearchText.isEmpty && filteredTags.isEmpty {
                        Text("Press Enter to create \"\(tagSearchText)\"")
                            .font(.groveBadge)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(.horizontal)
            }
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

    // MARK: - Resurfacing Section

    private var resurfacingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Resurfacing")
                .sectionHeaderStyle()
                .padding(.horizontal)

            if item.isResurfacingEligible {
                Toggle(isOn: Binding(
                    get: { !item.isResurfacingPaused },
                    set: { item.isResurfacingPaused = !$0 }
                )) {
                    Text("Active in resurfacing queue")
                        .font(.groveBodySmall)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.horizontal)

                if !item.isResurfacingPaused {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.groveBadge)
                                .foregroundStyle(Color.textSecondary)
                            Text("Interval: \(item.resurfaceIntervalDays) days")
                                .font(.groveMeta)
                                .foregroundStyle(Color.textSecondary)
                        }

                        if let nextDate = item.nextResurfaceDate {
                            HStack(spacing: 4) {
                                Image(systemName: item.isResurfacingOverdue ? "exclamationmark.circle" : "calendar.badge.clock")
                                    .font(.groveBadge)
                                    .foregroundStyle(item.isResurfacingOverdue ? Color.textPrimary : Color.textSecondary)
                                Text(item.isResurfacingOverdue ? "Overdue" : "Next: \(nextDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.groveMeta)
                                    .fontWeight(item.isResurfacingOverdue ? .semibold : .regular)
                                    .foregroundStyle(item.isResurfacingOverdue ? Color.textPrimary : Color.textSecondary)
                            }
                        }

                        if item.resurfaceCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.groveBadge)
                                    .foregroundStyle(Color.textSecondary)
                                Text("Resurfaced \(item.resurfaceCount) time\(item.resurfaceCount == 1 ? "" : "s")")
                                    .font(.groveMeta)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Text("Resurfacing paused for this item.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal)
                }
            } else {
                Text("Add annotations or connections to enable resurfacing.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Actions

    private func addTag(_ tag: Tag) {
        if !item.tags.contains(where: { $0.id == tag.id }) {
            item.tags.append(tag)
            item.updatedAt = .now
        }
        tagSearchText = ""
        isAddingTag = false
    }

    private func removeTag(_ tag: Tag) {
        item.tags.removeAll { $0.id == tag.id }
        item.updatedAt = .now
    }

    private func createAndAddTag() {
        let name = tagSearchText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        // Check for existing tag (case-insensitive)
        if let existing = allTags.first(where: { $0.name.lowercased() == name.lowercased() }) {
            addTag(existing)
            return
        }

        let tag = Tag(name: name, category: newTagCategory)
        modelContext.insert(tag)
        item.tags.append(tag)
        item.updatedAt = .now
        tagSearchText = ""
        newTagCategory = .custom
        isAddingTag = false
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
            Text("Inspector")
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal)
                .padding(.top)

            Text("Select an item to see details.")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal)

            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(Color.bgInspector)
    }
}

