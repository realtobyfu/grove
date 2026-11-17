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
    @State private var localSelectedBoardID: UUID?
    @State private var showNewBoardSheet = false
    @State private var showCaptureSheet = false

    var onOpenItem: ((Item) -> Void)? = nil
    var selectedItem: Binding<Item?>? = nil
    var openedItem: Binding<Item?>? = nil
    var selectedBoard: Binding<UUID?>? = nil
    /// Pushes the board's detail page. Without it the board header is hidden.
    var onOpenBoard: ((UUID) -> Void)? = nil

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

    private var selectedBoardModel: Board? {
        guard let selectedBoardID else { return nil }
        return boards.first(where: { $0.id == selectedBoardID })
    }

    /// Items scoped to the board filter (if any), before text search
    private var boardFilteredItems: [Item] {
        guard let boardID = selectedBoardID,
              let board = boards.first(where: { $0.id == boardID }) else {
            // Unkept newsletter issues live in the Newsletters tab, not here.
            return allItems.filter {
                ($0.status == .active || $0.status == .inbox) && !$0.isFeedSuggestion
            }
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
                GroveEmptyState(
                    title: "Nothing saved yet.",
                    detail: "Links and notes you save will be kept here.",
                    actionTitle: "Add link or note",
                    action: { showCaptureSheet = true }
                )
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                itemList
            }
        }
        .background(Color.bgPrimary)
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search items")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showCaptureSheet = true
                    } label: {
                        Label("Add link or note", systemImage: "square.and.pencil")
                    }
                    Button {
                        showNewBoardSheet = true
                    } label: {
                        Label("New board", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.medium)
                }
                .accessibilityLabel("Add")
            }
        }
        .sheet(isPresented: $showCaptureSheet) {
            CaptureSheetView(initialBoardID: selectedBoardModel?.id)
        }
        .sheet(isPresented: $showNewBoardSheet) {
            BoardEditorSheet(
                onSave: { title, icon in
                    let viewModel = BoardViewModel(modelContext: modelContext)
                    viewModel.createBoard(title: title, icon: icon)
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
                    .listRowBackground(Color.bgPrimary)
            }

            if let board = selectedBoardModel {
                if let onOpenBoard {
                    boardHeaderRow(board, onOpen: onOpenBoard)
                }
                if board.items.isEmpty {
                    emptyBoardState
                }
            }

            // Items
            ForEach(displayedItems) { item in
                openItemRow(item: item) {
                    MobileItemCardView(item: item)
                }
                .mobileItemContextMenu(item: item)
                .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                    dimensions[.leading]
                }
            }
            .listRowBackground(Color.bgPrimary)
            // Same inset as the chip bar, so chips and rows share one edge.
            .listRowInsets(EdgeInsets(
                top: Spacing.xsm,
                leading: LayoutDimensions.contentPaddingH,
                bottom: Spacing.xsm,
                trailing: LayoutDimensions.contentPaddingH
            ))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        .navigationDestination(for: MobileItemRoute.self) { route in
            MobileItemRouteDestinationView(route: route)
        }
    }

    // MARK: - Board filter chips

    private var boardFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                FilterChip(label: "All", isActive: selectedBoardID == nil) {
                    selectedBoardID = nil
                }

                ForEach(boards) { board in
                    FilterChip(label: board.title, isActive: selectedBoardID == board.id) {
                        selectedBoardID = board.id
                    }
                }
            }
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.vertical, Spacing.xs)
        }
    }

    // MARK: - Board header

    /// Table-of-contents entry for the filtered board: serif title, item count
    /// set like a page number, and a chevron into the board's own page.
    private func boardHeaderRow(_ board: Board, onOpen: @escaping (UUID) -> Void) -> some View {
        Button {
            onOpen(board.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(board.title)
                    .font(.groveListTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: Spacing.sm)

                Text("\(board.items.count)")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    .monospacedDigit()
                    .fixedSize()

                Image(systemName: "chevron.right")
                    .font(.groveMeta)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textMuted)
            }
            .frame(minHeight: LayoutDimensions.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(
            top: 0,
            leading: LayoutDimensions.contentPaddingH,
            bottom: 0,
            trailing: LayoutDimensions.contentPaddingH
        ))
        .listRowBackground(Color.bgPrimary)
        .accessibilityLabel("\(board.title), \(board.items.count) items")
        .accessibilityHint("Opens the board")
    }

    // MARK: - Empty board

    private var emptyBoardState: some View {
        GroveEmptyState(
            title: "Nothing on this board yet.",
            detail: "Tap + and choose Add link or note to put something here."
        )
        .listRowBackground(Color.bgPrimary)
        .listRowInsets(EdgeInsets(
            top: 0,
            leading: LayoutDimensions.contentPaddingH,
            bottom: 0,
            trailing: LayoutDimensions.contentPaddingH
        ))
        .listRowSeparator(.hidden)
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
            NavigationLink(value: MobileItemRoute(id: item.id)) {
                content()
            }
        }
    }
}
