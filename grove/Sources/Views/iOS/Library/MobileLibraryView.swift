import SwiftUI
import SwiftData

/// Library view for iOS — shows all items with board filter chips,
/// mirroring the macOS LibraryView pattern.
struct MobileLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(iPadReaderCoordinator.self) private var readerCoordinator: iPadReaderCoordinator?
    @Query(sort: \Item.updatedAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @State private var searchText: String = ""
    @State private var selectedBoardID: UUID?
    @State private var showNewBoardSheet = false

    var onOpenItem: ((Item) -> Void)? = nil
    var selectedItem: Binding<Item?>? = nil
    var openedItem: Binding<Item?>? = nil

    // MARK: - Computed

    /// Items scoped to the board filter (if any), before text search
    private var boardFilteredItems: [Item] {
        guard let boardID = selectedBoardID,
              let board = boards.first(where: { $0.id == boardID }) else {
            return allItems.filter { $0.status == .active || $0.status == .inbox }
        }
        if board.isSmart {
            return BoardViewModel.smartBoardItems(for: board, from: allItems)
        }
        return board.items.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Final displayed items after text search
    private var displayedItems: [Item] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return boardFilteredItems }
        return boardFilteredItems.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        Group {
            if allItems.isEmpty {
                ContentUnavailableView {
                    Label("No Items", systemImage: "tray")
                } description: {
                    Text("Items you capture will appear here.")
                }
            } else {
                itemList
            }
        }
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search items")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewBoardSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New board")
            }
        }
        .sheet(isPresented: $showNewBoardSheet) {
            BoardEditorSheet(
                onSave: { title, icon, color, nudgeFreq in
                    let viewModel = BoardViewModel(modelContext: modelContext)
                    viewModel.createBoard(title: title, icon: icon, color: color, nudgeFrequencyHours: nudgeFreq)
                }
            )
        }
    }

    // MARK: - Item list with board filter chips

    private var itemList: some View {
        List {
            // Board filter chip bar
            Section {
                boardFilterChips
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            // Items
            ForEach(displayedItems) { item in
                openItemRow(item: item) {
                    MobileItemCardView(item: item)
                }
                .mobileItemContextMenu(item: item)
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: Item.self) { item in
            MobileItemReaderView(item: item)
        }
    }

    // MARK: - Board filter chips

    private var boardFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                boardChip(title: "All", boardID: nil)

                ForEach(boards) { board in
                    boardChip(title: board.title, boardID: board.id)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func boardChip(title: String, boardID: UUID?) -> some View {
        let isActive = selectedBoardID == boardID
        return Button {
            selectedBoardID = boardID
        } label: {
            Text(title)
                .font(.groveTag)
                .foregroundStyle(isActive ? Color.textInverse : Color.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? Color.bgTagActive : Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? Color.clear : Color.borderTag, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func openItemRow<Content: View>(item: Item, @ViewBuilder content: () -> Content) -> some View {
        if let onOpenItem {
            Button {
                onOpenItem(item)
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else if let selectedItem, let openedItem {
            Button {
                selectedItem.wrappedValue = item
                openedItem.wrappedValue = item
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else if let readerCoordinator {
            Button {
                readerCoordinator.selectedItem = item
                readerCoordinator.openedItem = item
            } label: {
                content()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: item) {
                content()
            }
        }
    }
}
