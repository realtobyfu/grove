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
    /// Reports the note this session is writing as soon as it exists (and nil
    /// if it is removed again). The macOS rail uses it to pick the same note
    /// back up after another tab has had the right page.
    var onDraftItemChange: ((Item?) -> Void)? = nil

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
        .onChange(of: draft.item?.id) { onDraftItemChange?(draft.item) }
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

    /// No label: the right page's Note tab already says what this is, and a
    /// prompt has its own callout below. What is left are the two things a
    /// note can go on to be — a page, a flashcard — and the way out. The
    /// page is one glyph, the rarer actions sit in a menu, and Done is the
    /// one word, set as a button.
    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            Spacer(minLength: 0)

            if let onOpenAsPage {
                Button {
                    guard let note = draft.save(syncLinks: true) else { return }
                    onOpenAsPage(note)
                } label: {
                    WriterBarGlyph(symbol: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .disabled(!draft.hasText && draft.item == nil)
                .help("Open as a page")
                .accessibilityLabel("Open this note as a page")
            }

            Menu {
                if !referenceItems.isEmpty {
                    Menu("Cite a Source") {
                        ForEach(referenceItems) { source in
                            Button(source.title) {
                                insertReference(to: source)
                            }
                        }
                    }
                }
                Button("Make a Flashcard") {
                    guard let note = draft.save(syncLinks: true) else { return }
                    flashcardItem = note
                }
                .disabled(draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } label: {
                WriterBarGlyph(symbol: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More actions for this note")

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.grove(.secondary, size: .compact))
            .help("Save and close (\u{2318}\u{21A9})")
            .accessibilityHint("Saves and closes this panel.")
        }
        .padding(.horizontal, LayoutDimensions.writingGutter)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xs)
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

// MARK: - Top Bar Glyph

/// An icon control in the writer's top bar: the same square, ink and hover
/// wash as the editor's toolbar, so the two strips read as one family. The
/// iOS sheet gives it the full touch target.
private struct WriterBarGlyph: View {
    let symbol: String

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isHovering && isEnabled ? Color.textPrimary : Color.textSecondary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(isHovering && isEnabled ? Color.bgCardHover.opacity(0.6) : Color.clear)
            )
            #if os(iOS)
            .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
            #endif
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovering = $0 }
    }
}
