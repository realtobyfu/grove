import SQLiteData
import SwiftUI

/// Library view for iOS — shows all items with board filter chips,
/// mirroring the macOS LibraryView pattern.
struct MobileLibraryView: View {
    @Environment(iPadReaderCoordinator.self) private var readerCoordinator: iPadReaderCoordinator?
    @Fetch(Library.Request()) private var library = Library()

    @State private var searchText: String = ""
    @State private var localSelectedBoardID: UUID?
    @State private var showNewBoardSheet = false

    var onOpenItem: ((ItemGraph) -> Void)? = nil
    var selectedItem: Binding<ItemGraph?>? = nil
    var openedItem: Binding<ItemGraph?>? = nil
    var selectedBoard: Binding<UUID?>? = nil

    private var selectedBoardID: UUID? {
        get {
            if let selectedBoard { return selectedBoard.wrappedValue }
            return localSelectedBoardID
        }
        nonmutating set {
            if let selectedBoard { selectedBoard.wrappedValue = newValue }
            else { localSelectedBoardID = newValue }
        }
    }

    // MARK: - Computed

    /// Most recently changed first.
    private var allItems: [ItemGraph] {
        library.items.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var boards: [BoardGraph] { library.boards }

    /// Items scoped to the board filter (if any), before text search
    private var boardFilteredItems: [ItemGraph] {
        guard let boardID = selectedBoardID,
              let board = boards.first(where: { $0.id == boardID }) else {
            // Unkept newsletter issues live in the Newsletters tab, not here.
            return allItems.filter {
                ($0.status == .active || $0.status == .inbox) && !$0.isFeedSuggestion
            }
        }
        if board.isSmart {
            return BoardViewModel.smartBoardItems(for: board, from: allItems)
        }
        return board.items.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Final displayed items after text search
    private var displayedItems: [ItemGraph] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return boardFilteredItems }
        return boardFilteredItems.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        Group {
            if library.items.isEmpty {
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
                    let viewModel = BoardViewModel()
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
        .navigationDestination(for: MobileItemRoute.self) { route in
            MobileItemRouteDestinationView(route: route)
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
    private func openItemRow<Content: View>(item: ItemGraph, @ViewBuilder content: () -> Content) -> some View {
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
            NavigationLink(value: MobileItemRoute(id: item.id)) {
                content()
            }
        }
    }
}
