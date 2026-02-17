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
    @State private var viewMode: BoardViewMode = .grid
    @State private var sortOption: BoardSortOption = .dateAdded
    @State private var showNewNoteSheet = false
    @State private var selectedFilterTags: Set<UUID> = []
    @State private var collapsedSections: Set<String> = []

    // MARK: - Computed Properties

    private var allBoardTags: [Tag] {
        var tagSet: [UUID: Tag] = [:]
        for item in board.items {
            for tag in item.tags {
                tagSet[tag.id] = tag
            }
        }
        return tagSet.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var filteredItems: [Item] {
        guard !selectedFilterTags.isEmpty else { return board.items }
        return board.items.filter { item in
            let itemTagIDs = Set(item.tags.map(\.id))
            return selectedFilterTags.isSubset(of: itemTagIDs)
        }
    }

    private var sortedFilteredItems: [Item] {
        sortItems(filteredItems)
    }

    private var tagClusters: [TagCluster] {
        computeClusters(from: filteredItems)
    }

    var body: some View {
        VStack(spacing: 0) {
            if board.items.isEmpty {
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
                addNoteButton

                Spacer()

                sortPicker
                viewModePicker
            }
        }
        .sheet(isPresented: $showNewNoteSheet) {
            newNoteSheet
        }
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
            Image(systemName: board.icon ?? "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(board.title)
                .font(.title2)
                .fontWeight(.semibold)
            Text("No items yet. Add items to this board to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
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
                        }
                    }

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
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
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

    // MARK: - Clustering Algorithm

    private func computeClusters(from items: [Item]) -> [TagCluster] {
        guard !items.isEmpty else { return [] }

        // Build a map: for each item, get its tag IDs
        var itemTagSets: [(item: Item, tagIDs: Set<UUID>)] = items.map { item in
            (item, Set(item.tags.map(\.id)))
        }

        // Separate items with no tags
        let untaggedItems = itemTagSets.filter { $0.tagIDs.isEmpty }.map(\.item)
        itemTagSets = itemTagSets.filter { !$0.tagIDs.isEmpty }

        // Find tag groups by overlap: group items that share at least one tag
        var clusters: [TagCluster] = []
        var assigned: Set<UUID> = [] // item IDs already assigned

        // Build tag-to-items index
        var tagToItems: [UUID: [Item]] = [:]
        for entry in itemTagSets {
            for tagID in entry.tagIDs {
                tagToItems[tagID, default: []].append(entry.item)
            }
        }

        // Find the most shared tags and group items by them
        // Strategy: repeatedly pick the most popular tag combination, group items, remove them
        var remaining = itemTagSets

        while !remaining.isEmpty {
            // Count tag frequency among remaining items
            var tagFreq: [UUID: Int] = [:]
            for entry in remaining {
                for tagID in entry.tagIDs {
                    tagFreq[tagID, default: 0] += 1
                }
            }

            // Find the most common tag
            guard let topTagID = tagFreq.max(by: { $0.value < $1.value })?.key else { break }

            // Find all remaining items with this tag
            let matchingEntries = remaining.filter { $0.tagIDs.contains(topTagID) }
            let matchingItems = matchingEntries.map(\.item)

            guard !matchingItems.isEmpty else { break }

            // Find common tags across these items for the label
            let matchingTagSets = matchingEntries.map(\.tagIDs)
            let commonTagIDs: Set<UUID>
            if let first = matchingTagSets.first {
                commonTagIDs = matchingTagSets.dropFirst().reduce(first) { $0.intersection($1) }
            } else {
                commonTagIDs = []
            }

            // At minimum, include the top tag; also include any other tags shared by most items (>50%)
            var clusterTagIDs: Set<UUID> = [topTagID]
            for (tagID, count) in tagFreq {
                if tagID != topTagID && count > matchingItems.count / 2 {
                    // Check if this tag is shared by most of the matched items
                    let shareCount = matchingEntries.filter { $0.tagIDs.contains(tagID) }.count
                    if shareCount > matchingItems.count / 2 {
                        clusterTagIDs.insert(tagID)
                    }
                }
            }

            // Also add common tags
            clusterTagIDs = clusterTagIDs.union(commonTagIDs)

            // Resolve tag objects for the label
            let allTagObjects = allBoardTags
            let clusterTags = clusterTagIDs.compactMap { id in allTagObjects.first(where: { $0.id == id }) }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

            // Generate label from tag names
            let label = clusterTags.map(\.name).joined(separator: " & ")

            clusters.append(TagCluster(
                label: label.isEmpty ? "Uncategorized" : label,
                tags: clusterTags,
                items: matchingItems
            ))

            // Remove assigned items
            let matchingIDs = Set(matchingItems.map(\.id))
            remaining = remaining.filter { !matchingIDs.contains($0.item.id) }
        }

        // Add uncategorized section for untagged items
        if !untaggedItems.isEmpty {
            clusters.append(TagCluster(
                label: "Uncategorized",
                tags: [],
                items: untaggedItems
            ))
        }

        // If there are no tags at all, just show everything in one flat group
        if clusters.isEmpty {
            clusters.append(TagCluster(
                label: "All Items",
                tags: [],
                items: items
            ))
        }

        return clusters
    }

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
