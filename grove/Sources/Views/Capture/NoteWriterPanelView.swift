import SwiftUI
import SwiftData

// MARK: - NoteWriterPanelView

/// Note writer panel used both in the side write panel and the modal sheet flow.
struct NoteWriterPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @Binding var isPresented: Bool
    var currentBoardID: UUID?
    var prompt: String? = nil
    var editingItem: Item? = nil
    var isSidePanel: Bool = false
    var onCreated: ((Item) -> Void)?

    @State private var title = ""
    @State private var content = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        Group {
            if isSidePanel {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    if let prompt {
                        promptCallout(prompt)
                    }
                    titleField
                    Divider()
                        .padding(.horizontal, 40)
                    bodyEditor
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgPrimary)
                .onAppear {
                    if let editingItem {
                        title = editingItem.title
                        content = editingItem.content ?? ""
                    }
                    isTitleFocused = true
                }
                .onExitCommand {
                    dismiss()
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    if let prompt {
                        promptCallout(prompt)
                    }
                    titleField
                    Divider()
                        .padding(.horizontal, 40)
                    bodyEditor
                }
                .frame(minWidth: 640, idealWidth: 700, maxWidth: 820, minHeight: 480, idealHeight: 560, maxHeight: 760)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
                .onAppear {
                    isTitleFocused = true
                }
                .onExitCommand {
                    dismiss()
                }
            }
        }
        .background {
            // Hidden button to preserve ⌘↩ keyboard shortcut for save-and-close
            Button("") { dismiss() }
                .keyboardShortcut(.return, modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
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

    /// Persist content if non-empty. Called automatically on dismiss.
    private func saveContent() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedContent.isEmpty else { return }

        let noteTitle = trimmedTitle.isEmpty ? "Untitled Note" : trimmedTitle
        let noteContent = trimmedContent.isEmpty ? nil : trimmedContent

        if let editingItem {
            editingItem.title = noteTitle
            editingItem.content = noteContent
            editingItem.updatedAt = .now
            try? modelContext.save()
            onCreated?(editingItem)
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
            try? modelContext.save()
            onCreated?(note)
        }
    }

    private func dismiss() {
        saveContent()
        // Resign first responder before animating out so macOS doesn't leave
        // the window in a state where clicks stop reaching underlying views.
        NSApp.keyWindow?.makeFirstResponder(nil)
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}

