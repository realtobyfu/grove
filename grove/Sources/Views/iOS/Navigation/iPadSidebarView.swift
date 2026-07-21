import SwiftUI
import SwiftData

/// iPad sidebar for NavigationSplitView — mirrors macOS sidebar structure
/// but adds dedicated Inbox row and Settings row at bottom.
struct iPadSidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @State private var showNewBoardSheet = false
    @State private var boardToEdit: Board?
    @State private var boardToDelete: Board?

    /// Personal captures only — newsletter issues stay in the Newsletters tab.
    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox && !$0.isFeedSuggestion }.count
    }

    private var viewModel: BoardViewModel {
        BoardViewModel(modelContext: modelContext)
    }

    var body: some View {
        List(selection: $selection) {
            // MARK: - Main navigation
            Section {
                Label("Home", systemImage: "house")
                    .tag(SidebarItem.home)

                Label {
                    HStack {
                        Text("Inbox")
                        Spacer()
                        if inboxCount > 0 {
                            Text("\(inboxCount)")
                                .font(.groveMeta)
                                .foregroundStyle(Color.textTertiary)
                                .monospacedDigit()
                        }
                    }
                } icon: {
                    Image(systemName: "tray")
                }
                .tag(SidebarItem.inbox)

                Label("Library", systemImage: "books.vertical")
                    .tag(SidebarItem.library)
            }

            // MARK: - Boards
            Section {
                ForEach(boards) { board in
                    Label {
                        Text(board.title)
                    } icon: {
                        Image(systemName: board.icon ?? "folder")
                            .foregroundStyle(board.color.map { Color(hex: $0) } ?? Color.textSecondary)
                    }
                    .tag(SidebarItem.board(board.id))
                    #if os(iOS)
                    .dropDestination(for: URL.self) { urls, _ in
                        handleItemDrop(urls: urls, onto: board)
                    }
                    #endif
                    .contextMenu {
                        Button("Edit Board...") {
                            boardToEdit = board
                        }
                        Divider()
                        Button("Delete Board", role: .destructive) {
                            boardToDelete = board
                        }
                    }
                }
                .onMove { source, destination in
                    viewModel.moveBoard(from: source, to: destination, in: boards)
                }
            } header: {
                HStack(spacing: Spacing.sm) {
                    Text("Boards")
                        .sectionHeaderStyle()
                    Spacer()
                    Button {
                        showNewBoardSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                            .frame(width: LayoutDimensions.minTouchTarget,
                                   height: LayoutDimensions.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New board")
                }
            }

            // MARK: - Settings (bottom)
            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Grove")
        .sheet(isPresented: $showNewBoardSheet) {
            BoardEditorSheet(
                onSave: { title, icon, color, nudgeFreq in
                    viewModel.createBoard(title: title, icon: icon, color: color, nudgeFrequencyHours: nudgeFreq)
                }
            )
        }
        .sheet(item: $boardToEdit) { board in
            BoardEditorSheet(
                board: board,
                onSave: { title, icon, color, nudgeFreq in
                    viewModel.updateBoard(board, title: title, icon: icon, color: color, nudgeFrequencyHours: nudgeFreq)
                }
            )
        }
        // MARK: - Drop handling

        .alert(
            "Delete Board",
            isPresented: Binding(
                get: { boardToDelete != nil },
                set: { if !$0 { boardToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                boardToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let board = boardToDelete {
                    viewModel.deleteBoard(board)
                    if case .board(let id) = selection, id == board.id {
                        selection = nil
                    }
                }
                boardToDelete = nil
            }
        } message: {
            if let board = boardToDelete {
                Text("Are you sure you want to delete \"\(board.title)\"? Items in this board will not be deleted.")
            }
        }
    }

    // MARK: - Drop handling

    private func handleItemDrop(urls: [URL], onto board: Board) -> Bool {
        let itemVM = ItemViewModel(modelContext: modelContext)
        var handled = false
        for url in urls {
            var item: Item?
            if url.scheme == "grove", url.host == "item" {
                if let uuid = UUID(uuidString: url.lastPathComponent) {
                    item = allItems.first { $0.id == uuid }
                }
            } else {
                let urlString = url.absoluteString
                item = allItems.first { $0.sourceURL == urlString }
            }
            if let item {
                itemVM.assignToBoard(item, board: board)
                handled = true
            }
        }
        return handled
    }
}
