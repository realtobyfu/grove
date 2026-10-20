import SwiftUI
import SwiftData

// MARK: - NoteWriterPanelView

/// Note writer panel used both in the side write panel and the modal sheet flow.
struct NoteWriterPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @Binding var isPresented: Bool
    var currentBoardID: UUID?
    var prompt: String? = nil
    var editingItem: Item? = nil
    var isSidePanel: Bool = false
    var onCreated: ((Item) -> Void)?

    @State private var title = ""
    @State private var content = ""
    @State private var savedDraftItem: Item?
    @State private var flashcardItem: Item?
    @State private var saveError: String?
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        Group {
            if usesEdgeToEdgeLayout {
                editorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgPrimary)
                .onAppear {
                    configureInitialContent()
                }
            } else {
                editorContent
                .frame(minWidth: 640, idealWidth: 700, maxWidth: 820, minHeight: 480, idealHeight: 560, maxHeight: 760)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
                .onAppear {
                    configureInitialContent()
                }
            }
        }
        #if os(macOS)
        .onExitCommand {
            dismiss()
        }
        #endif
        .background {
            // Hidden button to preserve ⌘↩ keyboard shortcut for save-and-close
            Button("") { dismiss() }
                .keyboardShortcut(.return, modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .sheet(item: $flashcardItem) { note in
            NavigationStack {
                FlashcardEditorView(item: note, sourceQuote: note.content)
            }
            #if os(macOS)
            .frame(minWidth: 440, idealWidth: 500, minHeight: 520)
            #endif
        }
    }

    private var usesEdgeToEdgeLayout: Bool {
        if isSidePanel {
            return true
        }
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            if let saveError {
                Text(saveError)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 40)
                    .accessibilityLabel("Note save failed: \(saveError)")
            }
            if let prompt {
                promptCallout(prompt)
            }
            titleField
            Divider()
                .padding(.horizontal, 40)
            bodyEditor
        }
    }

    // MARK: - Prompt Callout

    private func promptCallout(_ text: String) -> some View {
        Text(text)
            .font(.groveGhostText)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 40)
            .padding(.bottom, 8)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Text(editingItem != nil ? "EDIT" : prompt != nil ? "WRITE" : "NOTE")
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)

            Spacer()

            if !referenceItems.isEmpty {
                Menu {
                    ForEach(referenceItems) { source in
                        Button(source.title) {
                            let reference = "[[\(source.title)]]"
                            if !content.contains(reference) {
                                content += content.isEmpty ? reference : "\n\n\(reference)"
                            }
                        }
                    }
                } label: {
                    Image(systemName: "link")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Insert a reference from this board")
                .accessibilityLabel("Insert a source reference")
            }

            Button {
                guard let note = saveContent(notifyCreated: false) else { return }
                flashcardItem = note
            } label: {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Save this note and make a flashcard from it")
            .accessibilityLabel("Make a flashcard from this note")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.groveBody)
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close note writer")
            .accessibilityHint("Saves and closes this panel.")
        }
        .padding(.horizontal, 40)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Title Field

    private var titleField: some View {
        TextField("", text: $title, prompt:
            Text("Title…")
                .foregroundStyle(Color.textMuted)
        )
        .textFieldStyle(.plain)
        .font(.groveItemTitle)
        .foregroundStyle(Color.textPrimary)
        .focused($isTitleFocused)
        .padding(.horizontal, 40)
        .padding(.vertical, 10)
    }

    // MARK: - Body Editor

    private var bodyEditor: some View {
        RichMarkdownEditor(text: $content, sourceItem: nil, minHeight: 200, proseMode: true)
            .frame(maxHeight: .infinity)
    }

    // MARK: - Actions

    /// True once the item being edited has been deleted out from under the
    /// panel. Writing to (or wiki-link syncing) a deleted model resurrects
    /// garbage in the store, so every save path bails on this.
    private var isEditingDeletedItem: Bool {
        guard let note = editingItem ?? savedDraftItem else { return false }
        return note.isDeleted || note.modelContext == nil
    }

    private var referenceItems: [Item] {
        let note = editingItem ?? savedDraftItem
        let sourceBoards: [Board]
        if let currentBoardID, let board = boards.first(where: { $0.id == currentBoardID }) {
            sourceBoards = [board]
        } else {
            sourceBoards = note?.boards ?? []
        }
        var seen: Set<UUID> = []
        return sourceBoards.flatMap(\.items)
            .filter { source in
                source.id != note?.id && source.status == .active && seen.insert(source.id).inserted
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Persist content if non-empty. Called automatically on dismiss.
    @discardableResult
    private func saveContent(notifyCreated: Bool = true) -> Item? {
        guard !isEditingDeletedItem else { return nil }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedContent.isEmpty else { return nil }

        let noteTitle = trimmedTitle.isEmpty ? "Untitled Note" : trimmedTitle
        let noteContent = trimmedContent.isEmpty ? nil : trimmedContent

        if let existingNote = editingItem ?? savedDraftItem {
            existingNote.title = noteTitle
            existingNote.content = noteContent
            existingNote.updatedAt = .now
            do {
                try modelContext.save()
                saveError = nil
            } catch {
                saveError = "Your note could not be saved. Please try again."
                return nil
            }
            // The editor runs with `sourceItem: nil`, so autocomplete never creates
            // connections here — sync typed [[wiki links]] into connections on save.
            WikiLinkSync.sync(item: existingNote, modelContext: modelContext)
            if notifyCreated { onCreated?(existingNote) }
            return existingNote
        } else {
            let board: Board? = currentBoardID.flatMap { id in
                boards.first(where: { $0.id == id })
            }
            let note = Item(title: noteTitle, type: .note)
            note.status = .active
            note.content = noteContent
            note.updatedAt = .now
            modelContext.insert(note)
            if let board { note.boards.append(board) }
            do {
                try modelContext.save()
                saveError = nil
            } catch {
                modelContext.delete(note)
                saveError = "Your note could not be saved. Please try again."
                return nil
            }
            savedDraftItem = note
            WikiLinkSync.sync(item: note, modelContext: modelContext)
            if notifyCreated { onCreated?(note) }
            return note
        }
    }

    private func configureInitialContent() {
        if let editingItem {
            title = editingItem.title
            content = editingItem.content ?? ""
        }
        isTitleFocused = true
    }

    private func dismiss() {
        let hasContent = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasContent, !isEditingDeletedItem, saveContent() == nil { return }
        // Resign first responder before animating out so macOS doesn't leave
        // the window in a state where clicks stop reaching underlying views.
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}
