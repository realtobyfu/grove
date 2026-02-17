import SwiftUI
import SwiftData

enum BoardViewMode: String, CaseIterable {
    case grid
    case list

    var iconName: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

enum BoardSortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case title = "Title"
    case engagementScore = "Engagement"
}

struct BoardDetailView: View {
    let board: Board
    @Environment(\.modelContext) private var modelContext
    @State private var viewMode: BoardViewMode = .grid
    @State private var sortOption: BoardSortOption = .dateAdded
    @State private var selectedItem: Item?
    @State private var showNewNoteSheet = false

    private var sortedItems: [Item] {
        let items = board.items
        switch sortOption {
        case .dateAdded:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .title:
            return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .engagementScore:
            return items.sorted { $0.engagementScore > $1.engagementScore }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if board.items.isEmpty {
                emptyState
            } else {
                switch viewMode {
                case .grid:
                    gridView
                case .list:
                    listView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(board.title)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                addNoteButton

                Spacer()

                sortPicker
                viewModePicker
            }
        }
        .sheet(isPresented: $showNewNoteSheet) {
            newNoteSheet
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: board.icon ?? "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(board.title)
                .font(.title2)
                .fontWeight(.semibold)
            Text("No items yet. Add items to this board to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)],
                spacing: 12
            ) {
                ForEach(sortedItems) { item in
                    ItemCardView(item: item)
                        .onTapGesture {
                            selectedItem = item
                        }
                        .overlay(
                            selectedItem?.id == item.id
                                ? RoundedRectangle(cornerRadius: 8).strokeBorder(.blue, lineWidth: 2)
                                : nil
                        )
                }
            }
            .padding()
        }
    }

    // MARK: - List View

    private var listView: some View {
        List(sortedItems, selection: Binding(
            get: { selectedItem?.id },
            set: { newID in
                selectedItem = sortedItems.first(where: { $0.id == newID })
            }
        )) { item in
            HStack(spacing: 10) {
                Image(systemName: item.type.iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .fontWeight(.medium)
                    if let url = item.sourceURL {
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                let connectionCount = item.outgoingConnections.count + item.incomingConnections.count
                if connectionCount > 0 {
                    Label("\(connectionCount)", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let annotationCount = item.annotations.count
                if annotationCount > 0 {
                    Label("\(annotationCount)", systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .tag(item.id)
        }
    }

    // MARK: - Toolbar Items

    private var addNoteButton: some View {
        Button {
            showNewNoteSheet = true
        } label: {
            Label("New Note", systemImage: "square.and.pencil")
        }
        .help("Add a new note to this board")
    }

    private var sortPicker: some View {
        Menu {
            ForEach(BoardSortOption.allCases, id: \.self) { option in
                Button {
                    sortOption = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort items")
    }

    private var viewModePicker: some View {
        Picker("View Mode", selection: $viewMode) {
            ForEach(BoardViewMode.allCases, id: \.self) { mode in
                Image(systemName: mode.iconName)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 80)
        .help("Toggle grid/list view")
    }

    // MARK: - New Note Sheet

    private var newNoteSheet: some View {
        NewNoteSheet { title, content in
            let viewModel = ItemViewModel(modelContext: modelContext)
            let note = viewModel.createNote(title: title)
            note.content = content
            viewModel.assignToBoard(note, board: board)
        }
    }
}

// MARK: - New Note Sheet

struct NewNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""

    let onCreate: (String, String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Note")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Title") {
                    TextField("Note title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .font(.body)
                        .frame(minHeight: 150)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    let noteTitle = title.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "Untitled Note"
                        : title
                    let noteContent = content.isEmpty ? nil : content
                    onCreate(noteTitle, noteContent)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 440, height: 400)
    }
}
