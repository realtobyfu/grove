import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case inbox
    case board(UUID)
    case tags
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var selection: SidebarItem? = .inbox
    @State private var showInspector = true
    @State private var selectedItem: Item?
    @State private var showNewNoteSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            HStack(spacing: 0) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector {
                    Divider()
                    if let selectedItem {
                        InspectorPanelView(item: selectedItem)
                            .frame(width: 280)
                    } else {
                        InspectorEmptyView()
                            .frame(width: 280)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation {
                            showInspector.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help(showInspector ? "Hide Inspector" : "Show Inspector")
                    .keyboardShortcut("]", modifiers: .command)
                }
            }
        }
        .frame(minWidth: 1200, minHeight: 800)
        .onChange(of: selection) {
            selectedItem = nil
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
        .keyboardShortcut(for: .newNote) {
            showNewNoteSheet = true
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .inbox:
            InboxTriageView(selectedItem: $selectedItem)
        case .board(let boardID):
            if let board = boards.first(where: { $0.id == boardID }) {
                BoardDetailView(board: board, selectedItem: $selectedItem)
            } else {
                PlaceholderView(
                    icon: "square.grid.2x2",
                    title: "Board",
                    message: "Board not found."
                )
            }
        case .tags:
            PlaceholderView(
                icon: "tag",
                title: "Tags",
                message: "Browse and manage your tags here."
            )
        case nil:
            PlaceholderView(
                icon: "leaf",
                title: "Grove",
                message: "Select an item from the sidebar to get started."
            )
        }
    }
}

struct PlaceholderView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InspectorPanelView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Query private var allTags: [Tag]
    @Query(sort: \Board.sortOrder) private var allBoards: [Board]
    @State private var tagSearchText = ""
    @State private var isAddingTag = false

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
            VStack(alignment: .leading, spacing: 16) {
                Text("Inspector")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top)

                metadataSection
                Divider().padding(.horizontal)
                tagSection
                Divider().padding(.horizontal)
                boardMembershipSection
                Divider().padding(.horizontal)
                connectionsSection

                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type
            HStack {
                Image(systemName: item.type.iconName)
                    .foregroundStyle(.secondary)
                Text(item.type.rawValue.capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Editable Title
            TextField("Title", text: $item.title)
                .textFieldStyle(.plain)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal)
                .onChange(of: item.title) {
                    item.updatedAt = .now
                }

            // Source URL
            if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(sourceURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal)
            }

            // Dates
            VStack(alignment: .leading, spacing: 4) {
                Label("Created: \(item.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Updated: \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Tag Section

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tags")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isAddingTag.toggle()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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
                    TextField("Search or create tag...", text: $tagSearchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit {
                            createAndAddTag()
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
                                                .font(.caption)
                                            Spacer()
                                            Text(tag.category.rawValue)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
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
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Board Membership Section

    private var boardMembershipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Boards")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if item.boards.isEmpty {
                Text("Not in any board")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
            } else {
                ForEach(item.boards) { board in
                    HStack(spacing: 6) {
                        if let hex = board.color {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 8, height: 8)
                        }
                        if let icon = board.icon {
                            Image(systemName: icon)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(board.title)
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Connections Section

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connections")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            let allConnections = item.outgoingConnections + item.incomingConnections
            if allConnections.isEmpty {
                Text("No connections yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
            } else {
                ForEach(allConnections) { connection in
                    connectionRow(connection)
                }
            }
        }
    }

    private func connectionRow(_ connection: Connection) -> some View {
        let isOutgoing = connection.sourceItem?.id == item.id
        let linkedItem = isOutgoing ? connection.targetItem : connection.sourceItem
        let typeLabel = connection.type.rawValue

        return HStack(spacing: 6) {
            Image(systemName: isOutgoing ? "arrow.right.circle" : "arrow.left.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(linkedItem?.title ?? "Unknown")
                    .font(.caption)
                    .lineLimit(1)
                Text(typeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal)
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

        let tag = Tag(name: name)
        modelContext.insert(tag)
        item.tags.append(tag)
        item.updatedAt = .now
        tagSearchText = ""
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
                .font(.caption2)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary)
        .clipShape(Capsule())
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Inspector")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            Text("Select an item to see details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Keyboard Shortcut Modifier

enum GroveShortcut {
    case newNote
}

extension View {
    func keyboardShortcut(for shortcut: GroveShortcut, action: @escaping () -> Void) -> some View {
        self.background(
            Button("") { action() }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
    }
}
