import SQLiteData
import SwiftUI

/// Full-screen note editor for iOS — title field, board chips, and a TextEditor
/// for markdown content. Saves on dismiss via .onDisappear.
struct MobileNoteEditorView: View {
    let item: ItemGraph
    @Dependency(\.defaultDatabase) private var database
    @Environment(\.dismiss) private var dismiss
    @FetchAll(Board.order(by: \.sortOrder)) private var boards

    // Seeded once and written back on the way out, so nothing arriving from the
    // database can reach text being typed.
    @State private var title: String
    @State private var content: String
    @State private var showBoardPicker = false
    @State private var flashcardSession: LearningEditorSession?

    init(item: ItemGraph) {
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
            if let board = item.board {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
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
                    .padding(.horizontal, LayoutDimensions.contentPaddingH)
                }
                .padding(.bottom, Spacing.sm)
            }

            Divider()

            // Content editor
            RichMarkdownEditor(text: $content, sourceItem: item, minHeight: 200)
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
                        saveChanges()
                        // The session keeps what it's given, and `item` isn't up
                        // to date with that save yet.
                        let saved = database.attemptRead { try ItemGraph.fetch(item.id, in: $0) } ?? nil
                        flashcardSession = LearningEditorSession(item: saved ?? item, sourceQuote: content)
                    } label: {
                        Label("Remember an insight", systemImage: "rectangle.on.rectangle")
                    }
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
        .sheet(item: $flashcardSession) { session in
            NavigationStack { FlashcardEditorView(item: session.item, sourceQuote: session.sourceQuote) }
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
                    let isAssigned = item.boardID == board.id
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
        let itemID = item.id
        let text = content
        database.attempt { db in
            try Item.modify(itemID, in: db) {
                if !trimmedTitle.isEmpty {
                    $0.title = trimmedTitle
                }
                $0.content = text
                $0.updatedAt = .now
            }
        }
        WikiLinkSync.sync(itemID)
    }

    private func toggleBoard(_ board: Board) {
        let viewModel = ItemViewModel()
        if item.boardID == board.id {
            viewModel.removeFromBoard(item.id, boardID: board.id)
        } else {
            viewModel.assignToBoard(item.id, board: board)
        }
    }
}
