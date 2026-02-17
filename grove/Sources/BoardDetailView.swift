import SwiftUI
import SwiftData

enum BoardViewMode: String, CaseIterable {
    case grid
    case list

    var iconName: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

enum BoardSortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case title = "Title"
    case engagementScore = "Engagement"
}

// MARK: - Tag Cluster Model

struct TagCluster: Identifiable {
    let id = UUID()
    let label: String
    let tags: [Tag]
    let items: [Item]
}

struct BoardDetailView: View {
    let board: Board
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @State private var viewMode: BoardViewMode = .grid
    @State private var sortOption: BoardSortOption = .dateAdded
    @State private var showNewNoteSheet = false
    @State private var selectedFilterTags: Set<UUID> = []
    @State private var collapsedSections: Set<String> = []

    /// The effective items for this board — smart boards compute from tag rules, regular boards use direct membership
    private var effectiveItems: [Item] {
        if board.isSmart {
            return BoardViewModel.smartBoardItems(for: board, from: allItems)
        }
        return board.items
    }

    /// Flat ordered list of all visible items for J/K navigation
    private var flatVisibleItems: [Item] {
        var result: [Item] = []
        for cluster in tagClusters {
            guard !collapsedSections.contains(cluster.label) else { continue }
            result.append(contentsOf: sortItems(cluster.items))
        }
        return result
    }

    // MARK: - Computed Properties

    private var allBoardTags: [Tag] {
        var tagSet: [UUID: Tag] = [:]
        for item in effectiveItems {
            for tag in item.tags {
                tagSet[tag.id] = tag
            }
        }
        return tagSet.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var filteredItems: [Item] {
        guard !selectedFilterTags.isEmpty else { return effectiveItems }
        return effectiveItems.filter { item in
            let itemTagIDs = Set(item.tags.map(\.id))
            return selectedFilterTags.isSubset(of: itemTagIDs)
        }
    }

    private var sortedFilteredItems: [Item] {
        sortItems(filteredItems)
    }

    private var tagClusters: [TagCluster] {
        TagService.improvedClusters(from: filteredItems, allBoardTags: allBoardTags)
    }

    var body: some View {
        VStack(spacing: 0) {
            if effectiveItems.isEmpty {
                emptyState
            } else {
                // Tag filter bar
                if !allBoardTags.isEmpty {
                    tagFilterBar
                }

                // Content
                switch viewMode {
                case .grid:
                    gridView
                case .list:
                    listView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(board.title)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if !board.isSmart {
                    addNoteButton
                }

                Spacer()

                if board.isSmart && !board.smartRuleTags.isEmpty {
                    smartBoardRuleIndicator
                }

                sortPicker
                viewModePicker
            }
        }
        .sheet(isPresented: $showNewNoteSheet) {
            newNoteSheet
        }
        .background(boardKeyboardHandlers)
    }

    // MARK: - Keyboard Handlers (J/K/Enter)

    private var boardKeyboardHandlers: some View {
        Group {
            // J — select next item
            Button("") { navigateItems(by: 1) }
                .keyboardShortcut("j", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // K — select previous item
            Button("") { navigateItems(by: -1) }
                .keyboardShortcut("k", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)

            // Enter — open selected item
            Button("") { openSelectedItem() }
                .keyboardShortcut(.return, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }

    private func navigateItems(by offset: Int) {
        let items = flatVisibleItems
        guard !items.isEmpty else { return }

        if let current = selectedItem,
           let currentIndex = items.firstIndex(where: { $0.id == current.id }) {
            let newIndex = max(0, min(items.count - 1, currentIndex + offset))
            selectedItem = items[newIndex]
        } else {
            // No selection — select first or last depending on direction
            selectedItem = offset > 0 ? items.first : items.last
        }
    }

    private func openSelectedItem() {
        guard let item = selectedItem else { return }
        openedItem = item
    }

    // MARK: - Tag Filter Bar

    private var tagFilterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(allBoardTags) { tag in
                        let isSelected = selectedFilterTags.contains(tag.id)
                        Button {
                            if isSelected {
                                selectedFilterTags.remove(tag.id)
                            } else {
                                selectedFilterTags.insert(tag.id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(tag.category.color)
                                    .frame(width: 6, height: 6)
                                Text(tag.name)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSelected ? tag.category.color.opacity(0.2) : Color.clear)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSelected ? tag.category.color.opacity(0.6) : Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !selectedFilterTags.isEmpty {
                        Button {
                            selectedFilterTags.removeAll()
                        } label: {
                            Text("Clear")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            Divider()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: board.isSmart ? "sparkles.rectangle.stack" : (board.icon ?? "square.grid.2x2"))
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(board.title)
                .font(.title2)
                .fontWeight(.semibold)
            if board.isSmart {
                Text("No items match the tag rules yet. Tag items to see them appear here automatically.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if !board.smartRuleTags.isEmpty {
                    HStack(spacing: 4) {
                        Text("Rules:")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(board.smartRuleTags.map(\.name).joined(separator: board.smartRuleLogic == .and ? " AND " : " OR "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No items yet. Add items to this board to get started.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(tagClusters) { cluster in
                    clusterSection(cluster: cluster, viewMode: .grid)
                }
            }
            .padding()
        }
    }

    // MARK: - List View

    private var listView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(tagClusters) { cluster in
                    clusterSection(cluster: cluster, viewMode: .list)
                }
            }
            .padding()
        }
    }

    // MARK: - Cluster Section

    @ViewBuilder
    private func clusterSection(cluster: TagCluster, viewMode: BoardViewMode) -> some View {
        let isCollapsed = collapsedSections.contains(cluster.label)
        let sortedItems = sortItems(cluster.items)

        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedSections.remove(cluster.label)
                    } else {
                        collapsedSections.insert(cluster.label)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text(cluster.label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("\(cluster.items.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())

                    if !cluster.tags.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(cluster.tags.prefix(3)) { tag in
                                Circle()
                                    .fill(tag.category.color)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Section content
            if !isCollapsed {
                switch viewMode {
                case .grid:
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(sortedItems) { item in
                            ItemCardView(item: item)
                                .onTapGesture(count: 2) {
                                    openedItem = item
                                    selectedItem = item
                                }
                                .onTapGesture(count: 1) {
                                    selectedItem = item
                                }
                                .overlay(
                                    selectedItem?.id == item.id
                                        ? RoundedRectangle(cornerRadius: 8).strokeBorder(.blue, lineWidth: 2)
                                        : nil
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: sortedItems.map(\.id))

                case .list:
                    VStack(spacing: 0) {
                        ForEach(sortedItems) { item in
                            listRow(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    openedItem = item
                                    selectedItem = item
                                }
                                .onTapGesture(count: 1) {
                                    selectedItem = item
                                }
                                .background(selectedItem?.id == item.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                .transition(.opacity.combined(with: .slide))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.2), value: sortedItems.map(\.id))
                }
            }
        }
    }

    private func listRow(item: Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.type.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .fontWeight(.medium)
                if let url = item.sourceURL {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            let connectionCount = item.outgoingConnections.count + item.incomingConnections.count
            if connectionCount > 0 {
                Label("\(connectionCount)", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let annotationCount = item.annotations.count
            if annotationCount > 0 {
                Label("\(annotationCount)", systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Toolbar Items

    private var smartBoardRuleIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "gearshape.2")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(board.smartRuleTags.map(\.name).joined(separator: board.smartRuleLogic == .and ? " & " : " | "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary)
        .clipShape(Capsule())
        .help("Smart board rules: \(board.smartRuleLogic == .and ? "AND" : "OR") logic")
    }

    private var addNoteButton: some View {
        Button {
            showNewNoteSheet = true
        } label: {
            Label("New Note", systemImage: "square.and.pencil")
        }
        .help("Add a new note to this board")
    }

    private var sortPicker: some View {
        Menu {
            ForEach(BoardSortOption.allCases, id: \.self) { option in
                Button {
                    sortOption = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort items")
    }

    private var viewModePicker: some View {
        Picker("View Mode", selection: $viewMode) {
            ForEach(BoardViewMode.allCases, id: \.self) { mode in
                Image(systemName: mode.iconName)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 80)
        .help("Toggle grid/list view")
    }

    // MARK: - New Note Sheet

    private var newNoteSheet: some View {
        NewNoteSheet { title, content in
            let viewModel = ItemViewModel(modelContext: modelContext)
            let note = viewModel.createNote(title: title)
            note.content = content
            viewModel.assignToBoard(note, board: board)
        }
    }

    // MARK: - Clustering
    // Clustering now uses TagService.improvedClusters() which groups by co-occurrence + similarity

    private func sortItems(_ items: [Item]) -> [Item] {
        switch sortOption {
        case .dateAdded:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .engagementScore:
            return items.sorted { $0.engagementScore > $1.engagementScore }
        }
    }
}

// MARK: - New Note Sheet

struct NewNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""

    let onCreate: (String, String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Note")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Title") {
                    TextField("Note title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .font(.body)
                        .frame(minHeight: 150)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    let noteTitle = title.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "Untitled Note"
                        : title
                    let noteContent = content.isEmpty ? nil : content
                    onCreate(noteTitle, noteContent)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 440, height: 400)
    }
}
