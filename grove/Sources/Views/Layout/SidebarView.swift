import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Binding var selectedConversation: Conversation?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var showNewBoardSheet = false
    @State private var showNewCourseSheet = false
    @State private var boardToEdit: Board?
    @State private var boardToDelete: Board?
    @State private var courseToDelete: Course?
    @State private var conversationToDelete: Conversation?
    @State private var isConversationsCollapsed = false

    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox }.count
    }

    private var recentConversations: [Conversation] {
        Array(conversations.filter { !$0.isArchived && $0.isSavedToHistory }.prefix(3))
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
                HStack(spacing: Spacing.sm) {
                    Text("Courses")
                        .sectionHeaderStyle()

                    Spacer()

                    Button {
                        showNewCourseSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textMuted)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("New Course")
                    .accessibilityLabel("New course")
                    .accessibilityHint("Create a course in the sidebar list.")
                }
                .contextMenu {
                    Button("New Course...") {
                        showNewCourseSheet = true
                    }
                }
            }

            if !recentConversations.isEmpty {
                Section {
                    if !isConversationsCollapsed {
                        ForEach(recentConversations) { conv in
                            Button {
                                NotificationCenter.default.post(name: .groveOpenConversation, object: conv)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(conv.displayTitle)
                                            .font(.groveBody)
                                            .foregroundStyle(Color.textPrimary)
                                            .lineLimit(1)
                                        Text(conv.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                            .font(.groveMeta)
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    conversationToDelete = conv
                                }
                            }
                            .listRowBackground(
                                selectedConversation?.id == conv.id
                                    ? Color.accentSelection.opacity(0.08)
                                    : Color.clear
                            )
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isConversationsCollapsed.toggle()
                        }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: isConversationsCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .frame(width: 12)

                            Text("Chats")
                                .sectionHeaderStyle()

                            Text("\(recentConversations.count)")
                                .font(.groveBadge)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentBadge)
                                .foregroundStyle(Color.textPrimary)
                                .clipShape(Capsule())

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Label("Graph", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(SidebarItem.graph)
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
        .alert(
            "Delete Conversation Permanently?",
            isPresented: Binding(
                get: { conversationToDelete != nil },
                set: { if !$0 { conversationToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                conversationToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let conversation = conversationToDelete {
                    if selectedConversation?.id == conversation.id {
                        selectedConversation = nil
                    }
                    modelContext.delete(conversation)
                    try? modelContext.save()
                }
                conversationToDelete = nil
            }
        } message: {
            if let conversation = conversationToDelete {
                Text("\"\(conversation.displayTitle)\" and \(conversation.messages.count) message(s) will be permanently deleted. This cannot be undone.")
            }
        }
    }
}
