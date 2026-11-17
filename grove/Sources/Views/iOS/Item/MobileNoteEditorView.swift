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
    @State private var flashcardSession: LearningEditorSession?

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
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: board.icon ?? "folder")
                                    .font(.groveMeta)
                                Text(board.title)
                                    .font(.groveMeta)
                            }
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: Radius.control))
                        }
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
                        flashcardSession = LearningEditorSession(item: item, sourceQuote: content)
                    } label: {
                        Label("Remember an insight", systemImage: "rectangle.on.rectangle")
                    }
                    Button {
                        showBoardPicker = true
                    } label: {
                        Label("Add to Board", systemImage: "folder.badge.plus")
                    }
                } label: {
                    // Not an ellipsis: the reader hosting this editor already
                    // has an overflow menu in the same toolbar.
                    Image(systemName: "plus.circle")
                        .fontWeight(.medium)
                }
                .accessibilityLabel("Add from this note")
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

    /// Multi-select membership toggles. Not BoardPickerView: that picker
    /// picks one board and dismisses, and cannot take a note off a board.
    @ViewBuilder
    private var boardPickerSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(boards) { board in
                        let isAssigned = item.boards.contains(where: { $0.id == board.id })
                        Button {
                            toggleBoard(board)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: board.icon ?? "folder")
                                    .font(.groveBodySecondary)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.textTertiary)
                                Text(board.title)
                                    .font(.groveListTitle)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: Spacing.sm)
                                Text("\(board.items.count)")
                                    .font(.groveMeta)
                                    .foregroundStyle(Color.textTertiary)
                                    .monospacedDigit()
                                Image(systemName: "checkmark")
                                    .font(.groveMeta)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.textPrimary)
                                    .opacity(isAssigned ? 1 : 0)
                            }
                            .frame(minHeight: LayoutDimensions.minTouchTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isAssigned ? .isSelected : [])
                        .listRowBackground(Color.bgPrimary)
                    }
                } footer: {
                    Text("Tap a board to add this note to it, or tap again to take it off.")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary)
            .navigationTitle("Boards")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Boards")
                        .font(.groveListTitle)
                        .foregroundStyle(Color.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showBoardPicker = false
                    } label: {
                        Text("Done")
                            .font(.groveBodyMedium)
                    }
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
        WikiLinkSync.sync(item: item, modelContext: modelContext)
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
