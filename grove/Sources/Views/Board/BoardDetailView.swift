import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum BoardViewMode: String, CaseIterable, Sendable {
    case grid
    case list

    var iconName: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

enum BoardSortOption: String, CaseIterable, Sendable {
    case dateAdded = "Date Added"
    case title = "Title"
    case depthScore = "Depth"
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
    @State private var showSynthesisSheet = false
    @State private var showExportSheet = false
    @State private var clusterSynthesisItems: [Item]?
    @State private var clusterSynthesisTitle: String = ""
    @State private var showClusterSynthesisSheet = false
    @State private var showLearningPathSheet = false
    @State private var itemToDelete: Item?

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
            // Capture bar — auto-assigns to this board
            if !board.isSmart {
                CaptureBarView(currentBoardID: board.id)
            }

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
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleVideoDrop(providers: providers)
        }
        .navigationTitle(board.title)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if !board.isSmart {
                    addNoteButton
                }

                learningPathButton
                synthesisButton
                exportButton

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
        .sheet(isPresented: $showSynthesisSheet) {
            SynthesisSheet(
                items: filteredItems,
                scopeTitle: board.title,
                board: board,
                onCreated: { item in
                    selectedItem = item
                    openedItem = item
                }
            )
        }
        .sheet(isPresented: $showExportSheet) {
            BoardExportSheet(board: board, items: effectiveItems)
        }
        .sheet(isPresented: $showClusterSynthesisSheet) {
            if let items = clusterSynthesisItems {
                SynthesisSheet(
                    items: items,
                    scopeTitle: clusterSynthesisTitle,
                    board: board,
                    onCreated: { item in
                        selectedItem = item
                        openedItem = item
                    }
                )
            }
        }
        .sheet(isPresented: $showLearningPathSheet) {
            LearningPathSheet(
                items: filteredItems,
                topic: board.title,
                board: board,
                onCreated: { _ in }
            )
        }
        .background(boardKeyboardHandlers)
        .alert(
            "Delete Item",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    if selectedItem?.id == item.id {
                        selectedItem = nil
                    }
                    if openedItem?.id == item.id {
                        openedItem = nil
                    }
                    modelContext.delete(item)
                    try? modelContext.save()
                }
                itemToDelete = nil
            }
        } message: {
            if let item = itemToDelete {
                Text("Are you sure you want to delete \"\(item.title)\"? This cannot be undone.")
            }
        }
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
                        let isActive = selectedFilterTags.contains(tag.id)
                        Button {
                            if isActive {
                                selectedFilterTags.remove(tag.id)
                            } else {
                                selectedFilterTags.insert(tag.id)
                            }
                        } label: {
                            Text(tag.name)
                                .font(.groveTag)
                                .foregroundStyle(isActive ? Color.textInverse : Color.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(isActive ? Color.bgTagActive : Color.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(isActive ? Color.clear : Color.borderTag, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if !selectedFilterTags.isEmpty {
                        Button {
                            selectedFilterTags.removeAll()
                        } label: {
                            Text("Clear")
                                .font(.groveBodySmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, Spacing.sm)
            }
            Divider()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: board.isSmart ? "sparkles.rectangle.stack" : (board.icon ?? "square.grid.2x2"))
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text(board.title)
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)
            if board.isSmart {
                Text("No items match the tag rules yet. Tag items to see them appear here automatically.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if !board.smartRuleTags.isEmpty {
                    HStack(spacing: 4) {
                        Text("Rules:")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                        Text(board.smartRuleTags.map(\.name).joined(separator: board.smartRuleLogic == .and ? " AND " : " OR "))
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } else {
                Text("No items yet. Add items to this board to get started.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
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

        VStack(alignment: .leading, spacing: Spacing.sm) {
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
                        .font(.groveBadge)
                        .foregroundStyle(Color.textMuted)
                        .frame(width: 12)

                    Text(cluster.label)
                        .sectionHeaderStyle()

                    Text("\(cluster.items.count)")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentBadge)
                        .clipShape(Capsule())

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Cluster-level synthesize button
            if cluster.items.count >= 2 {
                Button {
                    clusterSynthesisItems = cluster.items
                    clusterSynthesisTitle = cluster.label
                    showClusterSynthesisSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text("Synthesize")
                            .font(.groveBadge)
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentBadge)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Generate synthesis from this cluster")
            }

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
                                .selectedItemStyle(selectedItem?.id == item.id)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                .contextMenu { itemContextMenu(for: item) }
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
                                .selectedItemStyle(selectedItem?.id == item.id)
                                .transition(.opacity.combined(with: .slide))
                                .contextMenu { itemContextMenu(for: item) }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.borderPrimary, lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.2), value: sortedItems.map(\.id))
                }
            }
        }
    }

    private func listRow(item: Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.type.iconName)
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                if let url = item.sourceURL {
                    Text(url)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            GrowthStageIndicator(stage: item.growthStage)
                .help("\(item.growthStage.displayName) — \(item.depthScore) pts")

            let connectionCount = item.outgoingConnections.count + item.incomingConnections.count
            if connectionCount > 0 {
                Label("\(connectionCount)", systemImage: "link")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
            }

            if item.reflections.count > 0 {
                Label("\(item.reflections.count)", systemImage: "text.alignleft")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Toolbar Items

    private var smartBoardRuleIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "gearshape.2")
                .font(.groveBadge)
                .foregroundStyle(Color.textSecondary)
            Text(board.smartRuleTags.map(\.name).joined(separator: board.smartRuleLogic == .and ? " & " : " | "))
                .font(.groveMeta)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentBadge)
        .clipShape(Capsule())
        .help("Smart board rules: \(board.smartRuleLogic == .and ? "AND" : "OR") logic")
    }

    private var learningPathButton: some View {
        Button {
            showLearningPathSheet = true
        } label: {
            Label("Learning Path", systemImage: "list.number")
        }
        .help("Generate an ordered learning path from items in this board")
        .disabled(effectiveItems.count < 2)
    }

    private var synthesisButton: some View {
        Button {
            showSynthesisSheet = true
        } label: {
            Label("Synthesize", systemImage: "sparkles")
        }
        .help("Generate an AI synthesis note from items in this board")
        .disabled(effectiveItems.count < 2)
    }

    private var exportButton: some View {
        Button {
            showExportSheet = true
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .help("Export this board")
        .disabled(effectiveItems.isEmpty)
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

    // MARK: - Video Drag-and-Drop

    private func handleVideoDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                let path = url.path
                guard ItemViewModel.isSupportedVideoFile(path) else { return }
                nonisolated(unsafe) let context = modelContext
                nonisolated(unsafe) let boardRef = board
                Task { @MainActor in
                    let viewModel = ItemViewModel(modelContext: context)
                    let item = viewModel.createVideoItem(filePath: path, board: boardRef.isSmart ? nil : boardRef)
                    selectedItem = item
                }
            }
            handled = true
        }
        return handled
    }

    // MARK: - Item Context Menu

    @ViewBuilder
    private func itemContextMenu(for item: Item) -> some View {
        Button {
            openedItem = item
            selectedItem = item
        } label: {
            Label("Open", systemImage: "doc.text")
        }

        if let urlString = item.sourceURL, let url = URL(string: urlString) {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
        }

        Divider()

        if !board.isSmart {
            Button {
                let viewModel = ItemViewModel(modelContext: modelContext)
                viewModel.removeFromBoard(item, board: board)
            } label: {
                Label("Remove from Board", systemImage: "folder.badge.minus")
            }
        }

        Button(role: .destructive) {
            itemToDelete = item
        } label: {
            Label("Delete Item", systemImage: "trash")
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
        case .depthScore:
            return items.sorted { $0.depthScore > $1.depthScore }
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
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Title") {
                    TextField("Note title", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .font(.groveBody)
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .font(.groveBody)
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
