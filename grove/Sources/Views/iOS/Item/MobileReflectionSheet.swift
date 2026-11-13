import SwiftUI
import SwiftData

/// Sheet for viewing and editing reflections on an item, drawn in the Mac
/// reflections rail's grammar: ink-ruled rows, a mono type label, the quoted
/// highlight in serif italic above the reflection, the date in mono meta.
///
/// Only ever presented as a sheet (iPhone, and iPad in compact width), so it
/// owns its NavigationStack. A regular-width iPad keeps reflections in the
/// shared reader's right rail instead.
struct MobileReflectionSheet: View {
    let item: Item
    /// Set by the caller to open a specific block for editing. Consumed
    /// (reset to nil) once handled.
    var requestedEditBlock: Binding<ReflectionBlock?>? = nil
    /// Jump to the highlighted passage in the source article; nil when the
    /// item has no web-readable source.
    var onHighlightTap: ((String) -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var editingBlock: ReflectionBlock?
    @State private var newBlockType: ReflectionBlockType = .keyInsight
    @State private var newBlockContent = ""
    @State private var isAddingNew = false
    @State private var flashcardSession: LearningEditorSession?
    @FocusState private var isEditorFocused: Bool

    /// The Mac rail's ghost prompts, in its order: each starts a reflection
    /// of its type.
    private static let ghostPrompts: [(label: String, type: ReflectionBlockType)] = [
        ("Key claim?", .keyInsight),
        ("Connections?", .connection),
        ("Challenge?", .disagreement)
    ]

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
            .background(Color.bgPrimary)
            .navigationTitle("Reflections")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Reflections")
                        .font(.groveListTitle)
                        .foregroundStyle(Color.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    addMenu
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        commitPendingEdits()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.groveBodyMedium)
                            .foregroundStyle(Color.textPrimary)
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

    /// "+" in the toolbar: pick the type up front, as on the Mac.
    private var addMenu: some View {
        Menu {
            ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                Button {
                    startNewReflection(type: type)
                } label: {
                    Label(type.displayName, systemImage: type.systemImage)
                }
            }
        } label: {
            Image(systemName: "plus")
                .fontWeight(.medium)
                .foregroundStyle(Color.textPrimary)
                .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Add reflection")
    }

    // MARK: - Empty state

    /// The Mac rail's empty idiom: a serif line, the ghost prompts, and one
    /// way to start a blank reflection.
    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("No reflections yet.")
                        .font(.groveListTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Start with a question.")
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textMuted)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Self.ghostPrompts, id: \.label) { prompt in
                        ghostPromptButton(label: prompt.label, type: prompt.type)
                    }
                }

                Button("Add reflection") {
                    startNewReflection(type: .keyInsight)
                }
                .buttonStyle(.grove(.primary))
            }
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.vertical, Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ghostPromptButton(label: String, type: ReflectionBlockType) -> some View {
        Button {
            startNewReflection(type: type)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: type.systemImage)
                    .font(.groveMeta)
                Text(label)
                    .font(.groveBodySecondary)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: LayoutDimensions.minTouchTarget, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(Color.borderPrimary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) Start a \(type.displayName) reflection")
    }

    // MARK: - Reflection list

    private var reflectionList: some View {
        List {
            Section {
                if isAddingNew {
                    newReflectionEditor
                        .listRowBackground(Color.bgPrimary)
                }

                ForEach(sortedReflections) { block in
                    Group {
                        if editingBlock?.id == block.id {
                            editBlockView(block)
                        } else {
                            reflectionRow(block)
                        }
                    }
                    .listRowBackground(Color.bgPrimary)
                    .listRowSeparatorTint(Color.borderPrimary)
                }
                .onDelete(perform: deleteBlocks)
            } header: {
                HStack(spacing: Spacing.sm) {
                    Text("Reflections")
                        .sectionHeaderStyle()
                    Text("\(sortedReflections.count)")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Reflection row

    private func reflectionRow(_ block: ReflectionBlock) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text(block.blockType.displayName)
                    .sectionHeaderStyle()
                Spacer(minLength: Spacing.sm)
                Text(block.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
            }

            if let highlight = block.highlight, !highlight.isEmpty {
                highlightQuote(highlight)
            }

            if block.content.isEmpty {
                Text("Tap to add your reflection…")
                    .font(.groveGhostText)
                    .foregroundStyle(Color.textTertiary)
            } else {
                Text(block.content)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
            }

            Button {
                makeFlashcard(from: block)
            } label: {
                Label("Make a flashcard", systemImage: "rectangle.on.rectangle")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .frame(minHeight: LayoutDimensions.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: LayoutDimensions.minTouchTarget, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.textPrimary)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingBlock = block
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                editingBlock = block
            }
            Menu("Change Type") {
                typeOptions(for: block)
            }
            Button("Make a flashcard", systemImage: "rectangle.on.rectangle") {
                makeFlashcard(from: block)
            }
            if let highlight = block.highlight, !highlight.isEmpty, let onHighlightTap {
                Button("Show in article", systemImage: "text.magnifyingglass") {
                    onHighlightTap(highlight)
                }
            }
            Divider()
            Button(role: .destructive) {
                delete(block)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// The quoted passage in serif italic. Tapping it jumps to the passage
    /// when the source can be scrolled.
    @ViewBuilder
    private func highlightQuote(_ highlight: String) -> some View {
        let quote = Text(highlight)
            .font(.groveGhostText)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)

        if let onHighlightTap {
            Button {
                onHighlightTap(highlight)
            } label: {
                quote
                    .frame(minHeight: LayoutDimensions.minTouchTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show highlight in article")
            .accessibilityValue(highlight)
        } else {
            quote
        }
    }

    private func typeOptions(for block: ReflectionBlock) -> some View {
        ForEach(ReflectionBlockType.allCases, id: \.self) { type in
            Button {
                block.blockType = type
                try? modelContext.save()
            } label: {
                Label(type.displayName, systemImage: type.systemImage)
            }
        }
    }

    // MARK: - Type picker (editors)

    /// Mono type label that opens the type list — the row's own header,
    /// made editable.
    private func typeMenu(selection: Binding<ReflectionBlockType>) -> some View {
        Menu {
            Picker("Type", selection: selection) {
                ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.systemImage)
                        .tag(type)
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(selection.wrappedValue.displayName)
                    .sectionHeaderStyle()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
            }
            .frame(minHeight: LayoutDimensions.minTouchTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Reflection type")
        .accessibilityValue(selection.wrappedValue.displayName)
    }

    private func editorChrome<Content: View>(
        type: Binding<ReflectionBlockType>,
        closeLabel: String,
        onClose: @escaping () -> Void,
        @ViewBuilder editor: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                typeMenu(selection: type)
                Spacer()
                Button(closeLabel, action: onClose)
                    .font(.groveBodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .frame(minWidth: LayoutDimensions.minTouchTarget,
                           minHeight: LayoutDimensions.minTouchTarget)
                    .buttonStyle(.plain)
            }
            editor()
        }
        .padding(.leading, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.textPrimary)
                .frame(width: 2)
        }
    }

    // MARK: - New reflection editor

    private var newReflectionEditor: some View {
        editorChrome(
            type: $newBlockType,
            closeLabel: "Discard",
            onClose: { discardNewReflection() }
        ) {
            TextEditor(text: $newBlockContent)
                .font(.groveBody)
                .scrollContentBackground(.hidden)
                .frame(minHeight: LayoutDimensions.minTouchTarget * 2)
                .focused($isEditorFocused)
                .onChange(of: isEditorFocused) { _, focused in
                    if !focused { autoSaveNewReflection() }
                }
        }
    }

    // MARK: - Edit existing block

    private func editBlockView(_ block: ReflectionBlock) -> some View {
        editorChrome(
            type: Binding(
                get: { block.blockType },
                set: { newType in
                    block.blockType = newType
                    try? modelContext.save()
                }
            ),
            closeLabel: "Done",
            onClose: {
                try? modelContext.save()
                WikiLinkSync.sync(item: item, content: block.content, modelContext: modelContext)
                editingBlock = nil
            }
        ) {
            if let highlight = block.highlight, !highlight.isEmpty {
                highlightQuote(highlight)
            }
            TextEditor(text: Binding(
                get: { block.content },
                set: { newValue in
                    block.content = newValue
                    try? modelContext.save()
                }
            ))
            .font(.groveBody)
            .scrollContentBackground(.hidden)
            .frame(minHeight: LayoutDimensions.minTouchTarget * 2)
        }
    }

    // MARK: - Actions

    private func startNewReflection(type: ReflectionBlockType) {
        // A reflection already being written keeps its text; only its type
        // follows the new choice.
        newBlockType = type
        editingBlock = nil
        isAddingNew = true
        isEditorFocused = true
    }

    private func makeFlashcard(from block: ReflectionBlock) {
        flashcardSession = LearningEditorSession(item: item, reflection: block, sourceQuote: block.highlight ?? block.content)
    }

    /// Autosave: creates the reflection when the editor loses focus (if non-empty).
    private func autoSaveNewReflection() {
        let trimmed = newBlockContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let block = ReflectionBlock(
            item: item,
            blockType: newBlockType,
            content: trimmed,
            position: item.reflections.count
        )
        modelContext.insert(block)
        try? modelContext.save()
        WikiLinkSync.sync(item: item, content: trimmed, modelContext: modelContext)

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
            try? modelContext.save()
            WikiLinkSync.sync(item: item, content: editingBlock.content, modelContext: modelContext)
            self.editingBlock = nil
        }
    }

    private func delete(_ block: ReflectionBlock) {
        if editingBlock?.id == block.id { editingBlock = nil }
        modelContext.delete(block)
        try? modelContext.save()
    }

    private func deleteBlocks(at offsets: IndexSet) {
        let blocks = sortedReflections
        for index in offsets {
            if editingBlock?.id == blocks[index].id { editingBlock = nil }
            modelContext.delete(blocks[index])
        }
        try? modelContext.save()
    }
}
