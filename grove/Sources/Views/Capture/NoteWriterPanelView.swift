import SwiftUI
import SwiftData

// MARK: - NoteWriterPanelView

/// The quick note writer: the rail's writing mode on macOS (a note beside
/// whatever is in the main column, or an answer to a prompt) and the sheet on
/// iOS. A note that outgrows the rail opens as a page (`NotePageView`).
///
/// The draft saves itself as it is written; closing only ends the session.
struct NoteWriterPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @Binding var isPresented: Bool
    var currentBoardID: UUID?
    var prompt: String? = nil
    var editingItem: Item? = nil
    var isSidePanel: Bool = false
    // Declared before `onOpenAsPage` on purpose: call sites pass this one as
    // a trailing closure, and a trailing closure binds to the first closure
    // parameter.
    var onCreated: ((Item) -> Void)?
    /// When set, the top bar offers to continue the note as a full page.
    var onOpenAsPage: ((Item) -> Void)? = nil

    @State private var draft = NoteDraft()
    @State private var editorProxy = MarkdownEditingProxy()
    @State private var flashcardItem: Item?
    @FocusState private var isTitleFocused: Bool

    private var saveError: String? {
        draft.state == .failed ? "Your note could not be saved. Please try again." : nil
    }

    var body: some View {
        Group {
            if usesEdgeToEdgeLayout {
                editorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgPrimary)
                .onAppear {
                    configureInitialContent()
                }
                // The side panel shares the window's one rail, so chat or the
                // inspector can take it over mid-draft; keep what was written.
                // Also covers a sheet swiped away, which never reaches `dismiss()`.
                // After `dismiss()` this finds nothing left to write.
                .onDisappear {
                    draft.finish()
                }
            } else {
                editorContent
                .frame(minWidth: 640, idealWidth: 700, maxWidth: 820, minHeight: 480, idealHeight: 560, maxHeight: 760)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                )
                .onAppear {
                    configureInitialContent()
                }
            }
        }
        .onChange(of: draft.title) { draft.textDidChange() }
        .onChange(of: draft.content) { draft.textDidChange() }
        #if os(macOS)
        .onExitCommand {
            dismiss()
        }
        // Quitting does not run `onDisappear`; write whatever the autosave
        // has not reached yet.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            draft.save()
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
                    .padding(.horizontal, LayoutDimensions.writingGutter)
                    .accessibilityLabel("Note save failed: \(saveError)")
            }
            if let prompt {
                promptCallout(prompt)
            }
            titleField
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
            .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            .padding(.horizontal, LayoutDimensions.writingGutter)
            .padding(.bottom, Spacing.sm)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: Spacing.md) {
            Text(editingItem != nil ? "EDIT" : prompt != nil ? "WRITE" : "NOTE")
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)

            Spacer()

            if !referenceItems.isEmpty {
                Menu {
                    ForEach(referenceItems) { source in
                        Button(source.title) {
                            insertReference(to: source)
                        }
                    }
                } label: {
                    barLabel("Cite", systemImage: "link")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Insert a reference from this board at the cursor")
                .accessibilityLabel("Insert a source reference")
            }

            Button {
                guard let note = draft.save(syncLinks: true) else { return }
                flashcardItem = note
            } label: {
                barLabel("Card", systemImage: "rectangle.on.rectangle")
            }
            .buttonStyle(.plain)
            .disabled(draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Save this note and make a flashcard from it")
            .accessibilityLabel("Make a flashcard from this note")

            if let onOpenAsPage {
                Button {
                    guard let note = draft.save(syncLinks: true) else { return }
                    onOpenAsPage(note)
                } label: {
                    barLabel("Page", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .disabled(!draft.hasText && draft.item == nil)
                .help("Continue this note as a full page")
                .accessibilityLabel("Open this note as a page")
            }

            Button {
                dismiss()
            } label: {
                barLabel("Done", systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close note writer")
            .accessibilityHint("Saves and closes this panel.")
        }
        .padding(.horizontal, LayoutDimensions.writingGutter)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.sm)
    }

    /// In the rail the bar is set as words in the meta face, like the label
    /// it shares a line with. The sheet keeps the icons its toolbar had.
    @ViewBuilder
    private func barLabel(_ word: String, systemImage: String) -> some View {
        if isSidePanel {
            Text(word.uppercased())
                .font(.groveMeta)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .contentShape(Rectangle())
        } else {
            Image(systemName: systemImage)
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                .contentShape(Rectangle())
        }
    }

    /// Puts `[[Title]]` where the caret is. Appends only when no editor is
    /// mounted to take it.
    private func insertReference(to source: Item) {
        let reference = "[[\(source.title)]]"
        if editorProxy.isConnected {
            editorProxy.insertText(reference, cursorOffset: 0)
        } else if !draft.content.contains(reference) {
            draft.content += draft.content.isEmpty ? reference : "\n\n\(reference)"
        }
    }

    // MARK: - Title Field

    private var titleField: some View {
        TextField("", text: $draft.title, prompt:
            Text("Title")
                .foregroundStyle(Color.textMuted)
        )
        .textFieldStyle(.plain)
        .font(.groveTitleLarge)
        .foregroundStyle(Color.textPrimary)
        .focused($isTitleFocused)
        // Return in the title carries on into the body.
        .onSubmit { editorProxy.focus() }
        .padding(.horizontal, LayoutDimensions.writingGutter)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Body Editor

    private var bodyEditor: some View {
        RichMarkdownEditor(
            text: $draft.content,
            // Nil until the note exists; `[[links]]` typed before that are
            // turned into connections when the session ends.
            sourceItem: draft.item,
            minHeight: 200,
            proseMode: true,
            proxy: editorProxy,
            status: draft.state.label
        )
        .frame(maxHeight: .infinity)
    }

    // MARK: - Actions

    private var referenceItems: [Item] {
        let note = draft.item ?? editingItem
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

    private func configureInitialContent() {
        draft.configure(item: editingItem, boardID: currentBoardID, modelContext: modelContext)
        isTitleFocused = true
    }

    private func dismiss() {
        if draft.hasText || draft.item != nil {
            let note = draft.finish()
            // A failed save keeps the panel open with the text still in it.
            if draft.state == .failed { return }
            if let note { onCreated?(note) }
        }
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
