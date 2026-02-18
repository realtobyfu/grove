import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var showNewBoardSheet = false
    @State private var showNewCourseSheet = false
    @State private var boardToEdit: Board?
    @State private var boardToDelete: Board?
    @State private var boardToExport: Board?
    @State private var courseToDelete: Course?

    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox }.count
    }

    private var recentConversations: [Conversation] {
        Array(conversations.filter { !$0.isArchived }.prefix(3))
    }

    private var viewModel: BoardViewModel {
        BoardViewModel(modelContext: modelContext)
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label {
                    HStack {
                        Text("Home")
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
                    Image(systemName: "envelope")
                }
                .tag(SidebarItem.home)
            }

            Section {
                ForEach(boards) { board in
                    Label {
                        HStack(spacing: 6) {
                            Text(board.title)
                            if board.isSmart {
                                Image(systemName: "gearshape.2")
                                    .font(.groveBadge)
                                    .foregroundStyle(Color.textSecondary)
                                    .help("Smart Board — auto-populates by tag rules")
                            }
                        }
                    } icon: {
                        Image(systemName: board.isSmart ? "sparkles.rectangle.stack" : (board.icon ?? "folder"))
                            .foregroundStyle(board.color.map { Color(hex: $0) } ?? Color.textSecondary)
                    }
                    .tag(SidebarItem.board(board.id))
                    .contextMenu {
                        Button("Edit Board...") {
                            boardToEdit = board
                        }
                        Divider()
                        Button("Export Board...") {
                            boardToExport = board
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
                        .sectionHeaderStyle()
                    Spacer()
                    Button {
                        showNewBoardSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.groveMeta)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textMuted)
                    .help("Add Board")
                }
            }

            Section {
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
            } header: {
                HStack {
                    Text("Courses")
                        .sectionHeaderStyle()
                    Spacer()
                    Button {
                        showNewCourseSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.groveMeta)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textMuted)
                    .help("Add Course")
                }
            }

            if !recentConversations.isEmpty {
                Section {
                    ForEach(recentConversations) { conv in
                        Button {
                            NotificationCenter.default.post(name: .groveOpenConversation, object: conv)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conv.title)
                                    .font(.groveBody)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Text(conv.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.groveMeta)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Conversations")
                            .sectionHeaderStyle()
                        Spacer()
                        Button {
                            NotificationCenter.default.post(name: .groveToggleChat, object: nil)
                        } label: {
                            Image(systemName: "plus")
                                .font(.groveMeta)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.textMuted)
                        .help("New Chat")
                    }
                }
            }

            Section {
                Label("Graph", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(SidebarItem.graph)
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showNewBoardSheet) {
            BoardEditorSheet(
                onSave: { title, icon, color, nudgeFreq in
                    viewModel.createBoard(title: title, icon: icon, color: color, nudgeFrequencyHours: nudgeFreq)
                },
                onSaveSmart: { title, icon, color, tags, logic, nudgeFreq in
                    viewModel.createSmartBoard(title: title, icon: icon, color: color, ruleTags: tags, logic: logic, nudgeFrequencyHours: nudgeFreq)
                }
            )
        }
        .sheet(item: $boardToEdit) { board in
            BoardEditorSheet(
                board: board,
                onSave: { title, icon, color, nudgeFreq in
                    viewModel.updateBoard(board, title: title, icon: icon, color: color, nudgeFrequencyHours: nudgeFreq)
                },
                onSaveSmart: { title, icon, color, tags, logic, nudgeFreq in
                    viewModel.updateSmartBoard(board, title: title, icon: icon, color: color, ruleTags: tags, logic: logic, nudgeFrequencyHours: nudgeFreq)
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
        .sheet(item: $boardToExport) { board in
            BoardExportSheet(board: board, items: board.items)
        }
    }
}
