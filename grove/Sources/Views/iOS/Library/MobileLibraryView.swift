import SwiftUI
import SwiftData

/// Library view for iOS — shows searchable board list with NavigationLink
/// to board detail views.
struct MobileLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @State private var searchText: String = ""
    @State private var showNewBoardSheet = false

    private var filteredBoards: [Board] {
        if searchText.isEmpty {
            return boards
        }
        return boards.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if boards.isEmpty {
                ContentUnavailableView {
                    Label("No Boards", systemImage: "folder")
                } description: {
                    Text("Create a board to organize your items.")
                } actions: {
                    Button("Create Board") {
                        showNewBoardSheet = true
                    }
                }
            } else {
                boardList
            }
        }
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search boards")
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

    // MARK: - Board list (P4.1)

    private var boardList: some View {
        List {
            ForEach(filteredBoards) { board in
                NavigationLink(value: board) {
                    boardRow(board)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        let viewModel = BoardViewModel(modelContext: modelContext)
                        viewModel.deleteBoard(board)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: Board.self) { board in
            MobileBoardDetailView(board: board)
        }
    }

    private func boardRow(_ board: Board) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: board.icon ?? "folder")
                .foregroundStyle(board.color.map { Color(hex: $0) } ?? Color.textSecondary)
                .frame(width: 24)

            Text(board.title)
                .font(.groveBody)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text("\(board.items.count)")
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
        }
        .frame(minHeight: LayoutDimensions.minTouchTarget)
    }
}
