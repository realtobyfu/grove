import SwiftUI
import SwiftData

/// Board detail view for iOS — shows items in a board with sort picker.
/// Uses adaptive LazyVGrid that adjusts column count based on available width.
struct MobileBoardDetailView: View {
    let board: Board
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]

    @State private var sortOption: BoardSortOption = .dateAdded

    private var boardItems: [Item] {
        let items = allItems.filter { item in
            item.boards.contains(where: { $0.id == board.id })
        }
        return sortedItems(items)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 280), spacing: Spacing.md)]
    }

    var body: some View {
        Group {
            if boardItems.isEmpty {
                ContentUnavailableView {
                    Label("No Items", systemImage: "tray")
                } description: {
                    Text("Items added to this board will appear here.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Spacing.md) {
                        ForEach(boardItems) { item in
                            NavigationLink(value: item) {
                                MobileItemCardView(item: item)
                                    .cardStyle()
                                    .padding(.horizontal, Spacing.xs)
                            }
                            .buttonStyle(.plain)
                            .mobileItemContextMenu(item: item)
                        }
                    }
                    .padding(.horizontal, LayoutDimensions.contentPaddingH)
                    .padding(.top, Spacing.md)
                }
            }
        }
        .navigationTitle(board.title)
        .navigationDestination(for: Item.self) { item in
            MobileItemReaderView(item: item)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(BoardSortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    // MARK: - Sorting

    private func sortedItems(_ items: [Item]) -> [Item] {
        switch sortOption {
        case .manual:
            return items // board-specific order preserved from SwiftData
        case .dateAdded:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .depthScore:
            return items.sorted { $0.depthScore > $1.depthScore }
        }
    }
}
