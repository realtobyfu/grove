import SQLiteData
import SwiftUI

/// Bottom sheet for viewing and editing reflections on an item.
/// iPhone: presented as sheet with .medium/.large detents.
/// iPad: presented as inspector trailing column (caller uses .inspector modifier).
struct MobileReflectionSheet: View {
    let item: ItemGraph
    var onDismiss: (() -> Void)? = nil
    /// Set by the caller to open a specific block for editing. Consumed
    /// (reset to nil) once handled.
    var requestedEditBlock: Binding<ReflectionBlock?>? = nil
    /// Jump to the highlighted passage in the source article; nil when the
    /// item has no web-readable source.
    var onHighlightTap: ((String) -> Void)? = nil
    @Dependency(\.defaultDatabase) private var database
    @Environment(\.dismiss) private var dismiss

    /// The block in the editor. A copy, and the editor reads this one rather than
    /// the block in `item`: that arrives a moment after each write, so it can hold
    /// text from a keystroke ago, and showing it would undo typing and move the
    /// cursor. See `modifyEditingBlock`.
    @State private var editingBlock: ReflectionBlock?
    @State private var newBlockType: ReflectionBlockType = .keyInsight
    @State private var newBlockContent = ""
    @State private var isAddingNew = false
    @State private var flashcardSession: LearningEditorSession?
    @FocusState private var isEditorFocused: Bool

    private var sortedReflections: [ReflectionBlock] {
        item.reflections.sorted { $0.position < $1.position }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedReflections.isEmpty && !isAddingNew {
                    emptyState
                } else {
                    reflectionList
                }
            }
            .navigationTitle("Reflections")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingNew = true
                        isEditorFocused = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add reflection")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        commitPendingEdits()
                        if let onDismiss { onDismiss() } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onAppear { consumeRequestedEditBlock() }
            .onChange(of: requestedEditBlock?.wrappedValue?.id) {
                consumeRequestedEditBlock()
            }
            .sheet(item: $flashcardSession) { session in
                NavigationStack {
                    FlashcardEditorView(item: session.item, reflection: session.reflection, sourceQuote: session.sourceQuote)
                }
            }
        }
    }

    /// Opens the caller-requested block for editing, then clears the request.
    private func consumeRequestedEditBlock() {
        guard let binding = requestedEditBlock, let block = binding.wrappedValue else { return }
        editingBlock = block
        isAddingNew = false
        binding.wrappedValue = nil
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Reflections", systemImage: "text.bubble")
        } description: {
            Text("Add reflections to deepen your understanding of this item.")
        } actions: {
            Button("Add Reflection") {
                isAddingNew = true
                isEditorFocused = true
            }
        }
    }

    // MARK: - Reflection list

    private var reflectionList: some View {
        List {
            if isAddingNew {
                newReflectionEditor
            }

            ForEach(sortedReflections) { block in
                if editingBlock?.id == block.id {
                    editBlockView(block)
                } else {
                    reflectionRow(block)
                }
            }
            .onDelete(perform: deleteBlocks)
        }
        .listStyle(.plain)
    }

    // MARK: - Reflection row

    private func reflectionRow(_ block: ReflectionBlock) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: block.blockType.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Text(block.blockType.displayName)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text(block.createdAt, style: .relative)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
            }

            if let highlight = block.highlight, !highlight.isEmpty {
                let quote = Text(highlight)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
                    .italic()
                    .lineLimit(3)
                    .padding(.leading, Spacing.sm)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.textMuted.opacity(0.3))
                            .frame(width: 2)
                    }

                if let onHighlightTap {
                    Button {
                        onHighlightTap(highlight)
                    } label: {
                        quote
                            .frame(maxWidth: .infinity,
                                   minHeight: LayoutDimensions.minTouchTarget,
                                   alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show highlight in article")
                } else {
                    quote
                }
            }

            Text(block.content)
                .font(.groveBody)
                .foregroundStyle(Color.textPrimary)
            Button {
                flashcardSession = LearningEditorSession(item: item, reflection: block, sourceQuote: block.highlight ?? block.content)
            } label: {
                Label("Make a flashcard", systemImage: "rectangle.on.rectangle")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .frame(minHeight: LayoutDimensions.minTouchTarget)
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: LayoutDimensions.minTouchTarget)
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            editingBlock = block
        }
        .contextMenu {
            Button("Make a flashcard", systemImage: "rectangle.on.rectangle") {
                flashcardSession = LearningEditorSession(item: item, reflection: block, sourceQuote: block.highlight ?? block.content)
            }
        }
    }

    // MARK: - New reflection editor

    private var newReflectionEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Picker("Type", selection: $newBlockType) {
                    ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.systemImage)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    discardNewReflection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textMuted)
                }
                .frame(minWidth: LayoutDimensions.minTouchTarget,
                       minHeight: LayoutDimensions.minTouchTarget)
                .accessibilityLabel("Discard")
            }

            TextEditor(text: $newBlockContent)
                .font(.groveBody)
                .frame(minHeight: 80)
                .focused($isEditorFocused)
                .onChange(of: isEditorFocused) { _, focused in
                    if !focused { autoSaveNewReflection() }
                }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Edit existing block

    private func editBlockView(_ block: ReflectionBlock) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Picker("Type", selection: Binding(
                    get: { editingBlock?.blockType ?? block.blockType },
                    set: { newType in
                        modifyEditingBlock { $0.blockType = newType }
                    }
                )) {
                    ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.systemImage)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    WikiLinkSync.sync(item.id, content: editingBlock?.content ?? block.content)
                    editingBlock = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.textMuted)
                }
                .frame(minWidth: LayoutDimensions.minTouchTarget,
                       minHeight: LayoutDimensions.minTouchTarget)
                .accessibilityLabel("Done editing")
            }

            TextEditor(text: Binding(
                get: { editingBlock?.content ?? block.content },
                set: { newValue in
                    modifyEditingBlock { $0.content = newValue }
                }
            ))
            .font(.groveBody)
            .frame(minHeight: 80)
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Actions

    /// Changes the block in the editor, as it types, and keeps the row that comes back.
    private func modifyEditingBlock(_ body: (inout ReflectionBlock) -> Void) {
        guard let blockID = editingBlock?.id else { return }
        let saved = database.attempt { db in
            try ReflectionBlock.modify(blockID, in: db, body)
        } ?? nil
        if let saved {
            editingBlock = saved
        }
    }

    /// Autosave: creates the reflection when the editor loses focus (if non-empty).
    private func autoSaveNewReflection() {
        let trimmed = newBlockContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let itemID = item.id
        let blockType = newBlockType
        database.attempt { db in
            let block = ReflectionBlock(
                itemID: itemID,
                blockType: blockType,
                content: trimmed,
                position: try ReflectionBlock.nextPosition(onItem: itemID, in: db)
            )
            try ReflectionBlock.insert { block }.execute(db)
        }
        WikiLinkSync.sync(itemID, content: trimmed)

        newBlockContent = ""
        isAddingNew = false
    }

    /// Discard the in-progress new reflection without saving.
    private func discardNewReflection() {
        newBlockContent = ""
        isAddingNew = false
        isEditorFocused = false
    }

    /// Save any pending edits before dismissing.
    private func commitPendingEdits() {
        // Save in-progress new reflection
        autoSaveNewReflection()
        // Save any in-progress block edit
        if let editingBlock {
            WikiLinkSync.sync(item.id, content: editingBlock.content)
            self.editingBlock = nil
        }
    }

    private func deleteBlocks(at offsets: IndexSet) {
        let blockIDs = offsets.map { sortedReflections[$0].id }
        database.attempt { db in
            try ReflectionBlock.where { $0.id.in(blockIDs) }.delete().execute(db)
        }
    }
}
