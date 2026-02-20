import SwiftUI
import SwiftData

// MARK: - NoteWriterPanelView

/// Note writer panel used both in the side write panel and the modal sheet flow.
struct NoteWriterPanelView: View {
    private struct PendingSaveDraft {
        let title: String
        let content: String?
    }

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
    @State private var pendingSaveDraft: PendingSaveDraft?
    @State private var showSaveLocationDialog = false
    @State private var showBoardPicker = false
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
                    saveBar
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
                    saveBar
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
        .confirmationDialog(
            "Save Note",
            isPresented: $showSaveLocationDialog,
            titleVisibility: .visible
        ) {
            Button("Save Unfiled") {
                persistPendingSave(to: nil)
            }
            Button("Choose Board…") {
                showBoardPicker = true
            }
            Button("Cancel", role: .cancel) {
                pendingSaveDraft = nil
            }
        } message: {
            Text("This note is not in a board yet. Choose where to save it.")
        }
        .sheet(isPresented: $showBoardPicker) {
            SaveNoteBoardPickerSheet(
                boards: boards,
                onSelectBoard: { board in
                    persistPendingSave(to: board)
                },
                onCancel: {
                    showBoardPicker = false
                }
            )
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

    // MARK: - Save Bar

    private var saveBar: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.groveBody)
            .foregroundStyle(Color.textSecondary)

            Button {
                save()
            } label: {
                HStack(spacing: 4) {
                    Text("Save")
                    Text("⌘↩")
                        .font(.groveShortcut)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .font(.groveBodyMedium)
            .foregroundStyle(Color.textPrimary)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                      content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteTitle = trimmedTitle.isEmpty ? "Untitled Note" : trimmedTitle
        let noteContent = trimmedContent.isEmpty ? nil : trimmedContent

        if let editingItem {
            editingItem.title = noteTitle
            editingItem.content = noteContent
            editingItem.updatedAt = .now
            try? modelContext.save()
            onCreated?(editingItem)
            dismiss()
        } else {
            if let boardID = currentBoardID,
               let board = boards.first(where: { $0.id == boardID }) {
                persistNewNote(title: noteTitle, content: noteContent, board: board)
            } else if boards.isEmpty {
                persistNewNote(title: noteTitle, content: noteContent, board: nil)
            } else {
                pendingSaveDraft = PendingSaveDraft(title: noteTitle, content: noteContent)
                showSaveLocationDialog = true
            }
        }
    }

    private func persistNewNote(title: String, content: String?, board: Board?) {
        let note = Item(title: title, type: .note)
        note.status = .active
        note.content = content
        note.updatedAt = .now
        modelContext.insert(note)

        if let board {
            note.boards.append(board)
        }

        try? modelContext.save()
        onCreated?(note)
        dismiss()
    }

    private func persistPendingSave(to board: Board?) {
        guard let pendingSaveDraft else { return }
        showSaveLocationDialog = false
        showBoardPicker = false
        self.pendingSaveDraft = nil
        persistNewNote(
            title: pendingSaveDraft.title,
            content: pendingSaveDraft.content,
            board: board
        )
    }

    private func dismiss() {
        // Resign first responder before animating out so macOS doesn't leave
        // the window in a state where clicks stop reaching underlying views.
        NSApp.keyWindow?.makeFirstResponder(nil)
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}

private struct SaveNoteBoardPickerSheet: View {
    let boards: [Board]
    let onSelectBoard: (Board) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Choose Board")
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)

            if boards.isEmpty {
                Text("No boards available.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(boards) { board in
                            Button {
                                onSelectBoard(board)
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: board.icon ?? "folder")
                                        .font(.groveBodySmall)
                                        .foregroundStyle(Color.textSecondary)
                                        .frame(width: 14)

                                    Text(board.title)
                                        .font(.groveBody)
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)

                                    Spacer()
                                }
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                )
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 320)
        .background(Color.bgPrimary)
    }
}
