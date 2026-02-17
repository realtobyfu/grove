import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case inbox
    case board(UUID)
    case tags
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var selection: SidebarItem? = .inbox
    @State private var showInspector = true
    @State private var selectedItem: Item?
    @State private var showNewNoteSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            HStack(spacing: 0) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector {
                    Divider()
                    InspectorPanelView(item: selectedItem)
                        .frame(width: 280)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation {
                            showInspector.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help(showInspector ? "Hide Inspector" : "Show Inspector")
                    .keyboardShortcut("]", modifiers: .command)
                }
            }
        }
        .frame(minWidth: 1200, minHeight: 800)
        .sheet(isPresented: $showNewNoteSheet) {
            NewNoteSheet { title, content in
                let viewModel = ItemViewModel(modelContext: modelContext)
                let note = viewModel.createNote(title: title)
                note.content = content
                // If a board is selected, assign to it
                if case .board(let boardID) = selection,
                   let board = boards.first(where: { $0.id == boardID }) {
                    viewModel.assignToBoard(note, board: board)
                }
                selectedItem = note
            }
        }
        .keyboardShortcut(for: .newNote) {
            showNewNoteSheet = true
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .inbox:
            PlaceholderView(
                icon: "tray",
                title: "Inbox",
                message: "Captured items will appear here for triage."
            )
        case .board(let boardID):
            if let board = boards.first(where: { $0.id == boardID }) {
                BoardDetailView(board: board)
            } else {
                PlaceholderView(
                    icon: "square.grid.2x2",
                    title: "Board",
                    message: "Board not found."
                )
            }
        case .tags:
            PlaceholderView(
                icon: "tag",
                title: "Tags",
                message: "Browse and manage your tags here."
            )
        case nil:
            PlaceholderView(
                icon: "leaf",
                title: "Grove",
                message: "Select an item from the sidebar to get started."
            )
        }
    }
}

struct PlaceholderView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InspectorPanelView: View {
    let item: Item?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inspector")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            if let item {
                inspectorContent(for: item)
            } else {
                Text("Select an item to see details.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func inspectorContent(for item: Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Type
            HStack {
                Image(systemName: item.type.iconName)
                    .foregroundStyle(.secondary)
                Text(item.type.rawValue.capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Title
            Text(item.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal)

            Divider()
                .padding(.horizontal)

            // Dates
            VStack(alignment: .leading, spacing: 4) {
                Label(item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Boards
            if !item.boards.isEmpty {
                Divider()
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Boards")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    ForEach(item.boards) { board in
                        HStack(spacing: 4) {
                            if let hex = board.color {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 6, height: 6)
                            }
                            Text(board.title)
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Keyboard Shortcut Modifier

enum GroveShortcut {
    case newNote
}

extension View {
    func keyboardShortcut(for shortcut: GroveShortcut, action: @escaping () -> Void) -> some View {
        self.background(
            Button("") { action() }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
    }
}
