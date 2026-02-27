import SwiftUI
import SwiftData

/// Bottom sheet for viewing and editing reflections on an item.
/// iPhone: presented as sheet with .medium/.large detents.
/// iPad: presented as inspector trailing column (caller uses .inspector modifier).
struct MobileReflectionSheet: View {
    let item: Item
    var onDismiss: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var editingBlock: ReflectionBlock?
    @State private var newBlockType: ReflectionBlockType = .keyInsight
    @State private var newBlockContent = ""
    @State private var isAddingNew = false
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
        }
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
                Text(highlight)
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
            }

            Text(block.content)
                .font(.groveBody)
                .foregroundStyle(Color.textPrimary)
        }
        .frame(minHeight: LayoutDimensions.minTouchTarget)
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            editingBlock = block
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
                    get: { block.blockType },
                    set: { newType in
                        block.blockType = newType
                        try? modelContext.save()
                    }
                )) {
                    ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.systemImage)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    try? modelContext.save()
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
                get: { block.content },
                set: { newValue in
                    block.content = newValue
                    try? modelContext.save()
                }
            ))
            .font(.groveBody)
            .frame(minHeight: 80)
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Actions

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
        if editingBlock != nil {
            try? modelContext.save()
            editingBlock = nil
        }
    }

    private func deleteBlocks(at offsets: IndexSet) {
        let blocks = sortedReflections
        for index in offsets {
            modelContext.delete(blocks[index])
        }
        try? modelContext.save()
    }
}
