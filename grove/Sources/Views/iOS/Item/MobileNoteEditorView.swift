import SwiftUI
import SwiftData

/// Full-screen note editor for iOS — title field, board chips, and a TextEditor
/// for markdown content. Saves on dismiss via .onDisappear.
struct MobileNoteEditorView: View {
    let item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @State private var title: String
    @State private var content: String
    @State private var showBoardPicker = false

    init(item: Item) {
        self.item = item
        _title = State(initialValue: item.title)
        _content = State(initialValue: item.content ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            TextField("Title", text: $title)
                .font(.groveTitle)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)

            // Board chips
            if !item.boards.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(item.boards) { board in
                            HStack(spacing: 4) {
                                Image(systemName: board.icon ?? "folder")
                                    .font(.system(size: 10))
                                Text(board.title)
                                    .font(.groveMeta)
                            }
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Color.bgCard)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, LayoutDimensions.contentPaddingH)
                }
                .padding(.bottom, Spacing.sm)
            }

            Divider()

            // Content editor
            TextEditor(text: $content)
                .font(.groveBody)
                .foregroundStyle(Color.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, LayoutDimensions.contentPaddingH - 5) // TextEditor has inset
                .padding(.top, Spacing.sm)
        }
        .navigationTitle("Note")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showBoardPicker = true
                    } label: {
                        Label("Add to Board", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showBoardPicker) {
            boardPickerSheet
        }
        .onDisappear {
            saveChanges()
        }
    }

    // MARK: - Board picker

    @ViewBuilder
    private var boardPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(boards) { board in
                    let isAssigned = item.boards.contains(where: { $0.id == board.id })
                    Button {
                        toggleBoard(board)
                    } label: {
                        HStack {
                            Label(board.title, systemImage: board.icon ?? "folder")
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            if isAssigned {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Boards")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showBoardPicker = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func saveChanges() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            item.title = trimmedTitle
        }
        item.content = content
        item.updatedAt = .now
        try? modelContext.save()
    }

    private func toggleBoard(_ board: Board) {
        let viewModel = ItemViewModel(modelContext: modelContext)
        if item.boards.contains(where: { $0.id == board.id }) {
            viewModel.removeFromBoard(item, board: board)
        } else {
            viewModel.assignToBoard(item, board: board)
        }
    }
}
