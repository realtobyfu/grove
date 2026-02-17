import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @State private var showNewBoardSheet = false
    @State private var boardToEdit: Board?
    @State private var boardToDelete: Board?

    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox }.count
    }

    private var viewModel: BoardViewModel {
        BoardViewModel(modelContext: modelContext)
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label {
                    HStack {
                        Text("Inbox")
                        Spacer()
                        if inboxCount > 0 {
                            Text("\(inboxCount)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.red.opacity(0.8))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "tray")
                }
                .tag(SidebarItem.inbox)
            }

            Section {
                ForEach(boards) { board in
                    Label {
                        HStack(spacing: 6) {
                            if let hex = board.color {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 8, height: 8)
                            }
                            Text(board.title)
                            if board.isSmart {
                                Image(systemName: "gearshape.2")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .help("Smart Board — auto-populates by tag rules")
                            }
                        }
                    } icon: {
                        Image(systemName: board.isSmart ? "sparkles.rectangle.stack" : (board.icon ?? "folder"))
                    }
                    .tag(SidebarItem.board(board.id))
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
                HStack {
                    Text("Boards")
                    Spacer()
                    Button {
                        showNewBoardSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Add Board")
                }
            }

            Section {
                Label("Tags", systemImage: "tag")
                    .tag(SidebarItem.tags)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Grove")
        .sheet(isPresented: $showNewBoardSheet) {
            BoardEditorSheet(
                onSave: { title, icon, color in
                    viewModel.createBoard(title: title, icon: icon, color: color)
                },
                onSaveSmart: { title, icon, color, tags, logic in
                    viewModel.createSmartBoard(title: title, icon: icon, color: color, ruleTags: tags, logic: logic)
                }
            )
        }
        .sheet(item: $boardToEdit) { board in
            BoardEditorSheet(
                board: board,
                onSave: { title, icon, color in
                    viewModel.updateBoard(board, title: title, icon: icon, color: color)
                },
                onSaveSmart: { title, icon, color, tags, logic in
                    viewModel.updateSmartBoard(board, title: title, icon: icon, color: color, ruleTags: tags, logic: logic)
                }
            )
        }
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
}
