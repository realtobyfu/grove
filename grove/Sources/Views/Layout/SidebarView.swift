import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Course.createdAt) private var courses: [Course]

    @State private var showNewBoardSheet = false
    @State private var showNewCourseSheet = false
    @State private var boardToEdit: Board?
    @State private var boardToDelete: Board?
    @State private var courseToDelete: Course?
    @State private var isMoreExpanded = false

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
                        Text("Today")
                        Spacer()
                        if inboxCount > 0 {
                            Text("\(inboxCount)")
                                .font(.groveBadge)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentBadge)
                                .foregroundStyle(Color.textPrimary)
                                .clipShape(Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "sun.max")
                }
                .tag(SidebarItem.home)

                Label("Library", systemImage: "books.vertical")
                    .tag(SidebarItem.library)
            }

            Section {
                ForEach(boards) { board in
                    Label {
                        Text(board.title)
                    } icon: {
                        Image(systemName: board.icon ?? "folder")
                            .foregroundStyle(board.color.map { Color(hex: $0) } ?? Color.textSecondary)
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
                HStack(spacing: Spacing.sm) {
                    Text("Boards")
                        .sectionHeaderStyle()

                    Spacer()

                    Button {
                        showNewBoardSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("New Board")
                    .accessibilityLabel("New board")
                    .accessibilityHint("Create a board in the sidebar list.")
                }
                .contextMenu {
                    Button("New Board...") {
                        showNewBoardSheet = true
                    }
                }
            }

            Section {
                DisclosureGroup(isExpanded: $isMoreExpanded) {
                    ForEach(courses) { course in
                        Label {
                            HStack(spacing: 6) {
                                Text(course.title)
                                Spacer()
                                if course.totalCount > 0 {
                                    Text("\(course.completedCount)/\(course.totalCount)")
                                        .font(.groveBadge)
                                        .foregroundStyle(Color.textSecondary)
                                        .monospacedDigit()
                                }
                            }
                        } icon: {
                            Image(systemName: "graduationcap")
                        }
                        .tag(SidebarItem.course(course.id))
                        .contextMenu {
                            Button("Delete Course", role: .destructive) {
                                courseToDelete = course
                            }
                        }
                    }

                    Button {
                        showNewCourseSheet = true
                    } label: {
                        Label("New Course", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .listStyle(.sidebar)
        .onReceive(NotificationCenter.default.publisher(for: .groveNewBoard)) { _ in
            showNewBoardSheet = true
        }
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
        .sheet(isPresented: $showNewCourseSheet) {
            NewCourseSheet { course in
                selection = .course(course.id)
            }
        }
        .alert(
            "Delete Course",
            isPresented: Binding(
                get: { courseToDelete != nil },
                set: { if !$0 { courseToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                courseToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let course = courseToDelete {
                    if case .course(let id) = selection, id == course.id {
                        selection = nil
                    }
                    modelContext.delete(course)
                    try? modelContext.save()
                }
                courseToDelete = nil
            }
        } message: {
            if let course = courseToDelete {
                Text("Are you sure you want to delete \"\(course.title)\"? Lectures will not be deleted.")
            }
        }
    }
}
