import SwiftUI
import SwiftData
import AVKit

struct ItemReaderView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    // Annotation state (legacy)
    @State private var isAddingAnnotation = false
    @State private var newAnnotationText = ""
    @State private var editingAnnotationID: UUID?
    @State private var editAnnotationText = ""
    @State private var isEditingContent = false
    // Connection suggestions
    @State private var connectionSuggestions: [ConnectionSuggestion] = []
    @State private var showSuggestions = false
    @State private var showItemExportSheet = false
    // Video playback state
    @State private var videoCurrentTime: Double = 0
    @State private var videoDuration: Double = 0
    @State private var videoSeekTarget: Double? = nil
    // Reflection state
    @State private var isAddingBlock = false
    @State private var newBlockType: ReflectionBlockType = .keyInsight
    @State private var editingBlockID: UUID?
    @State private var editBlockContent = ""
    // Text selection for Reflect button
    @State private var selectedHighlightText: String?
    @State private var showReflectButton = false
    // Drag reordering state
    @State private var draggingBlock: ReflectionBlock?
    // Delete confirmation
    @State private var blockToDelete: ReflectionBlock?
    @State private var showDeleteConfirmation = false
    // AI reflection prompts
    @State private var aiPrompts: [ReflectionPrompt] = []
    @State private var isLoadingPrompts = false
    @State private var dismissedPromptIDs: Set<UUID> = []

    private var sortedReflections: [ReflectionBlock] {
        item.reflections.sorted { $0.position < $1.position }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HSplitView {
                // MARK: - Left Pane: Source Content (55%)
                leftPane
                    .frame(minWidth: 300, idealWidth: 550)

                // MARK: - Right Pane: Reflection Blocks (45%)
                rightPane
                    .frame(minWidth: 250, idealWidth: 450)
            }

            // Connection suggestion popover
            if showSuggestions && !connectionSuggestions.isEmpty {
                ConnectionSuggestionPopover(
                    sourceItem: item,
                    suggestions: connectionSuggestions,
                    onAccept: { suggestion in
                        acceptSuggestion(suggestion)
                    },
                    onDismiss: { suggestion in
                        dismissSuggestion(suggestion)
                    },
                    onDismissAll: {
                        dismissAllSuggestions()
                    }
                )
                .padding(.top, 8)
                .padding(.trailing, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            let recency = Date().timeIntervalSince(item.createdAt)
            if recency < 30 {
                triggerSuggestions()
            }
            loadAIPrompts()
        }
        .onChange(of: item.id) {
            showSuggestions = false
            connectionSuggestions = []
            isAddingBlock = false
            editingBlockID = nil
            selectedHighlightText = nil
            aiPrompts = []
            dismissedPromptIDs = []
            isLoadingPrompts = false
            loadAIPrompts()
        }
        .sheet(isPresented: $showItemExportSheet) {
            ItemExportSheet(items: [item])
        }
    }

    // MARK: - Left Pane

    private var leftPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                itemHeader
                Divider().padding(.horizontal)
                sourceContent
                    .padding()
                Divider().padding(.horizontal)
                annotationsSection
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgPrimary)
    }

    // MARK: - Right Pane

    private var rightPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Section header
                HStack {
                    Text("REFLECTIONS")
                        .sectionHeaderStyle()

                    Text("\(item.reflections.count)")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentBadge)
                        .clipShape(Capsule())

                    Spacer()

                    Button {
                        isAddingBlock = true
                        newBlockType = .keyInsight
                    } label: {
                        Label("Add Block", systemImage: "plus.circle")
                            .font(.groveBodySecondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Divider()
                    .padding(.horizontal, 16)

                // Add block picker
                if isAddingBlock {
                    addBlockPicker
                        .padding(.horizontal, 16)
                }

                // Reflection blocks or ghost prompts / AI prompts
                if sortedReflections.isEmpty && !isAddingBlock {
                    if isLoadingPrompts {
                        // Loading indicator while AI prompts are being generated
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating prompts...")
                                .font(.groveBodySecondary)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                    // Show AI prompts if available, otherwise static ghost prompts
                    let visiblePrompts = aiPrompts.filter { !dismissedPromptIDs.contains($0.id) }
                    if !visiblePrompts.isEmpty {
                        aiPromptRows(visiblePrompts)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    } else if !isLoadingPrompts {
                        ghostPrompts
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                } else {
                    ForEach(sortedReflections) { block in
                        HStack(alignment: .top, spacing: 4) {
                            // Drag handle
                            Image(systemName: "line.3.horizontal")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                                .frame(width: 12, height: 20)
                                .padding(.top, 14)
                                .onDrag {
                                    draggingBlock = block
                                    return NSItemProvider(object: block.id.uuidString as NSString)
                                }

                            reflectionBlockCard(block)
                        }
                        .onDrop(of: [.text], delegate: BlockDropDelegate(
                            targetBlock: block,
                            allBlocks: sortedReflections,
                            draggingBlock: $draggingBlock,
                            modelContext: modelContext
                        ))
                        .padding(.horizontal, 12)
                    }
                }

                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgInspector)
        .alert("Delete Reflection Block?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                blockToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let block = blockToDelete {
                    deleteBlock(block)
                }
                blockToDelete = nil
            }
        } message: {
            Text("This reflection block will be permanently removed.")
        }
    }

    // MARK: - Score Breakdown

    private var scoreBreakdownTooltip: String {
        let breakdown = item.scoreBreakdown
        if breakdown.isEmpty {
            return "\(item.growthStage.displayName) — 0 pts"
        }
        let lines = breakdown.map { "\($0.label): +\($0.points)" }
        return "\(item.growthStage.displayName) — \(item.depthScore) pts\n" + lines.joined(separator: "\n")
    }

    // MARK: - Header

    private var itemHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.type.iconName)
                    .foregroundStyle(Color.textSecondary)
                Text(item.type.rawValue.capitalized)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)

                if item.metadata["isAIGenerated"] == "true" {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text("AI-Generated Synthesis")
                            .font(.groveBadge)
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentBadge)
                    .clipShape(Capsule())
                }

                Spacer()

                Button {
                    showItemExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.groveMeta)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if item.type == .note {
                    Button {
                        let wasEditing = isEditingContent
                        isEditingContent.toggle()
                        if wasEditing {
                            // Mark AI-generated synthesis notes as edited
                            if item.metadata["isAIGenerated"] == "true" && item.metadata["isAIEdited"] != "true" {
                                item.metadata["isAIEdited"] = "true"
                            }
                            triggerSuggestions()
                        }
                    } label: {
                        Label(isEditingContent ? "Done" : "Edit", systemImage: isEditingContent ? "checkmark" : "pencil")
                            .font(.groveMeta)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Text(item.title)
                .font(.custom("Newsreader", size: 18))
                .fontWeight(.medium)
                .tracking(-0.36)
                .textSelection(.enabled)

            // AI Draft / Edited badge for synthesis notes
            if item.metadata["isAIGenerated"] == "true" {
                HStack(spacing: 4) {
                    Image(systemName: item.metadata["isAIEdited"] == "true" ? "pencil" : "sparkles")
                        .font(.system(size: 9))
                    Text(item.metadata["isAIEdited"] == "true" ? "Edited" : "AI Draft")
                        .font(.groveBadge)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentBadge)
                .clipShape(Capsule())
            }

            if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
                if item.metadata["videoLocalFile"] == "true", let path = item.metadata["originalPath"] {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.groveMeta)
                        Text(path)
                            .font(.groveMeta)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .foregroundStyle(Color.textSecondary)
                } else {
                    Link(destination: URL(string: sourceURL) ?? URL(string: "about:blank")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.groveMeta)
                            Text(sourceURL)
                                .font(.groveMeta)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            HStack(spacing: 16) {
                Label(item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                Label("\(item.annotations.count) annotations", systemImage: "note.text")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                Label("\(item.reflections.count) reflections", systemImage: "text.alignleft")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                // Growth stage indicator with tooltip breakdown
                HStack(spacing: 4) {
                    GrowthStageIndicator(stage: item.growthStage, showLabel: true)
                    Text("·")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                    Text("\(item.depthScore) pts")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
                .help(scoreBreakdownTooltip)
            }
        }
        .padding()
    }

    // MARK: - Source Content (left pane body)

    @ViewBuilder
    private var sourceContent: some View {
        if item.type == .video, let videoURL = localVideoURL {
            VStack(spacing: 8) {
                VideoPlayerView(
                    url: videoURL,
                    currentTime: $videoCurrentTime,
                    duration: $videoDuration,
                    seekToTime: videoSeekTarget
                )
                .frame(minHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text(videoCurrentTime.formattedTimestamp)
                        .font(.groveMeta)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                    Text("/")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                    Text(videoDuration.formattedTimestamp)
                        .font(.groveMeta)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    if let path = item.metadata["originalPath"] {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                }

                if let content = item.content, !content.isEmpty {
                    Divider()
                    SelectableMarkdownView(
                        markdown: content,
                        onSelectText: { text in
                            selectedHighlightText = text
                        }
                    )
                }
            }
        } else if isEditingContent && item.type == .note {
            WikiLinkTextEditor(
                text: Binding(
                    get: { item.content ?? "" },
                    set: {
                        item.content = $0.isEmpty ? nil : $0
                        item.updatedAt = .now
                    }
                ),
                sourceItem: item,
                minHeight: 200
            )
        } else if let content = item.content, !content.isEmpty {
            SelectableMarkdownView(
                markdown: content,
                onSelectText: { text in
                    selectedHighlightText = text
                }
            )
        } else {
            Text("No content available.")
                .font(.groveBody)
                .foregroundStyle(Color.textTertiary)
                .italic()
        }

        // Reflect from selection button
        if let highlight = selectedHighlightText, !highlight.isEmpty {
            HStack {
                Spacer()
                Button {
                    createBlockFromHighlight(highlight)
                } label: {
                    Label("Reflect on Selection", systemImage: "text.quote")
                        .font(.groveBodySecondary)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.textPrimary)

                Button {
                    selectedHighlightText = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
            }
            .padding(.top, 4)
        }
    }

    /// Resolve the local video file URL for this item
    private var localVideoURL: URL? {
        guard item.type == .video else { return nil }
        if let path = item.metadata["originalPath"] {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                return url
            }
        }
        if let urlString = item.sourceURL, urlString.hasPrefix("file://"),
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    // MARK: - Ghost Prompts

    private var ghostPrompts: some View {
        VStack(alignment: .leading, spacing: 12) {
            ghostPromptRow(
                text: "What is the key claim here?",
                blockType: .keyInsight
            )
            ghostPromptRow(
                text: "How does this connect to what you know?",
                blockType: .connection
            )
            ghostPromptRow(
                text: "What would you challenge?",
                blockType: .disagreement
            )
        }
    }

    // MARK: - AI Prompt Rows

    private func aiPromptRows(_ prompts: [ReflectionPrompt]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(prompts) { prompt in
                HStack(spacing: 8) {
                    Image(systemName: prompt.suggestedBlockType.systemImage)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 16)

                    Text(prompt.text)
                        .font(.groveGhostText)
                        .foregroundStyle(Color.textTertiary)

                    Spacer()

                    // Dismiss button
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            _ = dismissedPromptIDs.insert(prompt.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            Color.borderTagDashed,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    createBlock(type: prompt.suggestedBlockType, content: prompt.text, highlight: nil)
                    _ = dismissedPromptIDs.insert(prompt.id)
                }
            }
        }
    }

    private func ghostPromptRow(text: String, blockType: ReflectionBlockType) -> some View {
        Button {
            createBlock(type: blockType, content: "", highlight: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: blockType.systemImage)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 16)
                Text(text)
                    .font(.groveGhostText)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
            }
            .padding(12)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.borderPrimary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Block Picker

    private var addBlockPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHOOSE BLOCK TYPE")
                .sectionHeaderStyle()

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 6) {
                ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                    Button {
                        createBlock(type: type, content: "", highlight: nil)
                        isAddingBlock = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: type.systemImage)
                                .font(.system(size: 14))
                            Text(type.displayName)
                                .font(.groveBodySmall)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.borderPrimary, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Cancel") {
                isAddingBlock = false
            }
            .font(.groveBodySecondary)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.borderPrimary, lineWidth: 1)
        )
    }

    // MARK: - Reflection Block Card

    private func reflectionBlockCard(_ block: ReflectionBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: type label + actions
            HStack(spacing: 6) {
                Image(systemName: block.blockType.systemImage)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Text(block.blockType.displayName)
                    .font(.groveBadge)
                    .tracking(0.5)
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                Text(block.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)

                Menu {
                    // Change block type
                    Menu("Change Type") {
                        ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                            Button {
                                block.blockType = type
                                try? modelContext.save()
                            } label: {
                                Label(type.displayName, systemImage: type.systemImage)
                            }
                        }
                    }
                    Button {
                        editingBlockID = block.id
                        editBlockContent = block.content
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        blockToDelete = block
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }

            // Highlight (linked source text)
            if let highlight = block.highlight, !highlight.isEmpty {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.textPrimary)
                        .frame(width: 2)
                    Text(highlight)
                        .font(.groveGhostText)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.leading, 8)
                        .padding(.vertical, 4)
                }
                .padding(.leading, 4)
            }

            // Content or edit mode
            if editingBlockID == block.id {
                editBlockEditor(block)
            } else if block.content.isEmpty {
                // Inline editing for empty blocks — auto-enter edit mode
                Button {
                    editingBlockID = block.id
                    editBlockContent = block.content
                } label: {
                    Text("Click to add your reflection...")
                        .font(.groveGhostText)
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.bgPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            } else {
                // Render content as markdown, click to edit
                Button {
                    editingBlockID = block.id
                    editBlockContent = block.content
                } label: {
                    MarkdownTextView(markdown: block.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentSelection)
                .frame(width: 2)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.borderPrimary, lineWidth: 1)
        )
    }

    // MARK: - Block Editor

    private func editBlockEditor(_ block: ReflectionBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WikiLinkTextEditor(
                text: $editBlockContent,
                sourceItem: item,
                minHeight: 60
            )

            HStack {
                Button("Cancel") {
                    editingBlockID = nil
                    editBlockContent = ""
                }
                .font(.groveBodySecondary)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save") {
                    saveEditedBlock(block)
                }
                .font(.groveBodySecondary)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.textPrimary)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    // MARK: - Block CRUD

    private func createBlock(type: ReflectionBlockType, content: String, highlight: String?) {
        let nextPosition = (sortedReflections.last?.position ?? -1) + 1
        let block = ReflectionBlock(
            item: item,
            blockType: type,
            content: content,
            highlight: highlight,
            position: nextPosition
        )
        modelContext.insert(block)
        item.reflections.append(block)
        item.updatedAt = .now
        try? modelContext.save()

        // Auto-enter edit mode for the new block
        editingBlockID = block.id
        editBlockContent = content
    }

    private func createBlockFromHighlight(_ highlight: String) {
        createBlock(type: .keyInsight, content: "", highlight: highlight)
        selectedHighlightText = nil
    }

    private func saveEditedBlock(_ block: ReflectionBlock) {
        block.content = editBlockContent.trimmingCharacters(in: .whitespacesAndNewlines)
        item.updatedAt = .now
        try? modelContext.save()
        editingBlockID = nil
        editBlockContent = ""

        // Trigger connection suggestions after reflection save
        triggerSuggestions()
    }

    private func deleteBlock(_ block: ReflectionBlock) {
        item.reflections.removeAll { $0.id == block.id }
        modelContext.delete(block)
        item.updatedAt = .now
        try? modelContext.save()
    }

    // MARK: - Annotations (legacy)

    private var sortedAnnotations: [Annotation] {
        item.annotations.sorted { $0.createdAt < $1.createdAt }
    }

    private var annotationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ANNOTATIONS")
                    .sectionHeaderStyle()

                Text("\(item.annotations.count)")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentBadge)
                    .clipShape(Capsule())

                Spacer()

                Button {
                    isAddingAnnotation = true
                    newAnnotationText = ""
                } label: {
                    if isVideoItem {
                        Label("Annotate at \(videoCurrentTime.formattedTimestamp)", systemImage: "plus.circle")
                            .font(.groveMeta)
                    } else {
                        Label("Add Annotation", systemImage: "plus.circle")
                            .font(.groveMeta)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isAddingAnnotation {
                newAnnotationEditor
            }

            if sortedAnnotations.isEmpty && !isAddingAnnotation {
                Text("No annotations yet. Add one to capture your thoughts.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(sortedAnnotations) { annotation in
                    annotationCard(annotation)
                }
            }
        }
    }

    private var newAnnotationEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Annotation")
                .font(.groveBadge)
                .foregroundStyle(Color.textSecondary)

            WikiLinkTextEditor(
                text: $newAnnotationText,
                sourceItem: item,
                minHeight: 80
            )

            if isVideoItem {
                HStack(spacing: 4) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.caption2)
                    Text("Timestamp: \(videoCurrentTime.formattedTimestamp)")
                        .font(.caption2)
                }
                .foregroundStyle(Color.textSecondary)
            }

            Text("Supports markdown: **bold**, *italic*, `code`, # headings, [links](url), [[wiki-links]]")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)

            HStack {
                Button("Cancel") {
                    isAddingAnnotation = false
                    newAnnotationText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save") {
                    saveNewAnnotation()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.textPrimary)
                .disabled(newAnnotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
    }

    private var isVideoItem: Bool {
        item.type == .video && localVideoURL != nil
    }

    private func annotationCard(_ annotation: Annotation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isVideoItem, let position = annotation.position {
                    Button {
                        videoSeekTarget = Double(position)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                                .font(.groveMeta)
                            Text(Double(position).formattedTimestamp)
                                .font(.groveMeta)
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to \(Double(position).formattedTimestamp) in video")
                } else {
                    Label(annotation.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                Menu {
                    Button {
                        editingAnnotationID = annotation.id
                        editAnnotationText = annotation.content
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleteAnnotation(annotation)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }

            if editingAnnotationID == annotation.id {
                editAnnotationEditor(annotation)
            } else {
                MarkdownTextView(markdown: annotation.content)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
    }

    private func editAnnotationEditor(_ annotation: Annotation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WikiLinkTextEditor(
                text: $editAnnotationText,
                sourceItem: item,
                minHeight: 60
            )

            HStack {
                Button("Cancel") {
                    editingAnnotationID = nil
                    editAnnotationText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save") {
                    saveEditedAnnotation(annotation)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(editAnnotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Annotation Actions

    private func saveNewAnnotation() {
        let content = newAnnotationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let timestamp: Int? = isVideoItem ? Int(videoCurrentTime) : nil
        let annotation = Annotation(item: item, content: content, position: timestamp)
        modelContext.insert(annotation)
        item.annotations.append(annotation)
        item.updatedAt = .now
        try? modelContext.save()

        newAnnotationText = ""
        isAddingAnnotation = false

        triggerSuggestions()
    }

    private func saveEditedAnnotation(_ annotation: Annotation) {
        let content = editAnnotationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        annotation.content = content
        item.updatedAt = .now
        try? modelContext.save()

        editingAnnotationID = nil
        editAnnotationText = ""
    }

    private func deleteAnnotation(_ annotation: Annotation) {
        item.annotations.removeAll { $0.id == annotation.id }
        modelContext.delete(annotation)
        item.updatedAt = .now
        try? modelContext.save()
    }

    // MARK: - AI Reflection Prompts

    private func loadAIPrompts() {
        // Only generate if item has no reflections
        guard item.reflections.isEmpty else { return }
        guard LLMServiceConfig.isConfigured else { return }

        isLoadingPrompts = true
        Task {
            let service = ReflectionPromptService()
            let prompts = await service.generatePrompts(for: item, in: modelContext)
            isLoadingPrompts = false
            if !prompts.isEmpty {
                withAnimation(.easeOut(duration: 0.2)) {
                    aiPrompts = prompts
                }
            }
        }
    }

    // MARK: - Connection Suggestions

    private func triggerSuggestions() {
        Task {
            let service = ConnectionSuggestionService(modelContext: modelContext)
            let suggestions = await service.suggestConnectionsAsync(for: item)
            if !suggestions.isEmpty {
                withAnimation(.easeOut(duration: 0.25)) {
                    connectionSuggestions = suggestions
                    showSuggestions = true
                }
            }
        }
    }

    private func acceptSuggestion(_ suggestion: ConnectionSuggestion) {
        let viewModel = ItemViewModel(modelContext: modelContext)
        guard let connection = viewModel.createConnection(source: item, target: suggestion.targetItem, type: suggestion.suggestedType) else { return }
        // Store LLM reason as connection note
        connection.note = suggestion.reason
        connection.isAutoGenerated = true
        try? modelContext.save()
        let service = ConnectionSuggestionService(modelContext: modelContext)
        service.recordAccepted(sourceItem: item, targetItem: suggestion.targetItem)
        withAnimation {
            connectionSuggestions.removeAll { $0.id == suggestion.id }
            if connectionSuggestions.isEmpty {
                showSuggestions = false
            }
        }
    }

    private func dismissSuggestion(_ suggestion: ConnectionSuggestion) {
        let service = ConnectionSuggestionService(modelContext: modelContext)
        service.dismissSuggestion(sourceItemID: item.id, targetItemID: suggestion.targetItem.id)
        withAnimation {
            connectionSuggestions.removeAll { $0.id == suggestion.id }
            if connectionSuggestions.isEmpty {
                showSuggestions = false
            }
        }
    }

    private func dismissAllSuggestions() {
        let service = ConnectionSuggestionService(modelContext: modelContext)
        for suggestion in connectionSuggestions {
            service.dismissSuggestion(sourceItemID: item.id, targetItemID: suggestion.targetItem.id)
        }
        withAnimation {
            connectionSuggestions = []
            showSuggestions = false
        }
    }
}

// MARK: - Selectable Markdown View (NSTextView-backed for text selection)

struct SelectableMarkdownView: NSViewRepresentable {
    let markdown: String
    var onSelectText: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectText: onSelectText)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        scrollView.borderType = .noBorder

        updateTextView(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onSelectText = onSelectText
        textView.delegate = nil
        updateTextView(textView)
        textView.delegate = context.coordinator
    }

    private func updateTextView(_ textView: NSTextView) {
        let attributed = markdownToAttributedString(markdown)
        textView.textStorage?.setAttributedString(attributed)
    }

    private func markdownToAttributedString(_ md: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = md.components(separatedBy: "\n")
        var i = 0

        let bodyFont = NSFont(name: "IBMPlexSans-Regular", size: 13)
            ?? NSFont.systemFont(ofSize: 13)
        let bodyColor = NSColor.textColor
        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineSpacing = 4
        bodyParagraph.paragraphSpacing = 8

        while i < lines.count {
            let line = lines[i]

            // Code block
            if line.hasPrefix("```") {
                i += 1
                var codeLines: [String] = []
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }

                let codeFont = NSFont(name: "IBMPlexMono", size: 12)
                    ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                let codeParagraph = NSMutableParagraphStyle()
                codeParagraph.lineSpacing = 2
                codeParagraph.paragraphSpacingBefore = 8
                codeParagraph.paragraphSpacing = 8

                let codeStr = NSAttributedString(string: codeLines.joined(separator: "\n") + "\n", attributes: [
                    .font: codeFont,
                    .foregroundColor: bodyColor,
                    .paragraphStyle: codeParagraph,
                    .backgroundColor: NSColor.windowBackgroundColor.withAlphaComponent(0.5)
                ])
                result.append(codeStr)
                continue
            }

            // Heading
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if level >= 1 && level <= 6 && !text.isEmpty {
                    let headingSize: CGFloat = level == 1 ? 22 : level == 2 ? 18 : level == 3 ? 16 : 14
                    let headingFont = NSFont(name: "Newsreader", size: headingSize)
                        ?? NSFont.systemFont(ofSize: headingSize, weight: .semibold)
                    let headingParagraph = NSMutableParagraphStyle()
                    headingParagraph.paragraphSpacingBefore = level == 1 ? 12 : 8
                    headingParagraph.paragraphSpacing = 4

                    let headingStr = NSAttributedString(string: text + "\n", attributes: [
                        .font: headingFont,
                        .foregroundColor: bodyColor,
                        .paragraphStyle: headingParagraph
                    ])
                    result.append(headingStr)
                    i += 1
                    continue
                }
            }

            // Empty line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Paragraph
            var paragraphLines: [String] = [line]
            i += 1
            while i < lines.count {
                let nextLine = lines[i]
                if nextLine.trimmingCharacters(in: .whitespaces).isEmpty
                    || nextLine.hasPrefix("#")
                    || nextLine.hasPrefix("```") {
                    break
                }
                paragraphLines.append(nextLine)
                i += 1
            }

            let paragraphText = paragraphLines.joined(separator: "\n")
            let paraStr = NSAttributedString(string: paragraphText + "\n", attributes: [
                .font: bodyFont,
                .foregroundColor: bodyColor,
                .paragraphStyle: bodyParagraph
            ])
            result.append(paraStr)
        }

        return result
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectText: ((String) -> Void)?

        init(onSelectText: ((String) -> Void)?) {
            self.onSelectText = onSelectText
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0,
               let text = textView.textStorage?.attributedSubstring(from: selectedRange).string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onSelectText?(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}

// MARK: - Markdown Text View

struct MarkdownTextView: View {
    let markdown: String
    var onWikiLinkTap: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case codeBlock(language: String?, code: String)
        case bulletList(items: [String])
        case paragraph(text: String)
    }

    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Code block
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n")
                ))
                if i < lines.count { i += 1 }
                continue
            }

            // Heading
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if level >= 1 && level <= 6 && !text.isEmpty {
                    blocks.append(.heading(level: level, text: text))
                    i += 1
                    continue
                }
            }

            // Bullet list (- or * prefix)
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                var listItems: [String] = []
                while i < lines.count {
                    let current = lines[i].trimmingCharacters(in: .whitespaces)
                    if current.hasPrefix("- ") {
                        listItems.append(String(current.dropFirst(2)))
                    } else if current.hasPrefix("* ") {
                        listItems.append(String(current.dropFirst(2)))
                    } else if current.isEmpty {
                        break
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.bulletList(items: listItems))
                continue
            }

            // Empty line — skip
            if trimmedLine.isEmpty {
                i += 1
                continue
            }

            // Paragraph: collect consecutive non-empty, non-special lines
            var paragraphLines: [String] = [line]
            i += 1
            while i < lines.count {
                let nextLine = lines[i]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty
                    || nextLine.hasPrefix("#")
                    || nextLine.hasPrefix("```")
                    || nextTrimmed.hasPrefix("- ")
                    || nextTrimmed.hasPrefix("* ") {
                    break
                }
                paragraphLines.append(nextLine)
                i += 1
            }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: "\n")))
        }

        return blocks
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .codeBlock(let language, let code):
            SyntaxHighlightedCodeView(code: code, language: language)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, itemText in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2022}")
                            .font(.custom("IBMPlexSans-Regular", size: 13))
                            .foregroundStyle(Color.textSecondary)
                        renderInlineMarkdown(itemText)
                    }
                }
            }

        case .paragraph(let text):
            renderParagraphWithWikiLinks(text)
        }
    }

    @ViewBuilder
    private func renderInlineMarkdown(_ text: String) -> some View {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .font(.custom("IBMPlexSans-Regular", size: 13))
                .tint(Color.textSecondary)
        } else {
            Text(text)
                .font(.custom("IBMPlexSans-Regular", size: 13))
        }
    }

    @ViewBuilder
    private func renderParagraphWithWikiLinks(_ text: String) -> some View {
        let segments = parseWikiLinks(in: text)
        if segments.contains(where: { $0.isWikiLink }) {
            segments.reduce(Text("")) { result, segment in
                if segment.isWikiLink {
                    let linkText = Text(segment.text)
                        .foregroundColor(Color.textSecondary)
                        .underline()
                    return result + linkText
                } else {
                    if let attributed = try? AttributedString(markdown: segment.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        return result + Text(attributed)
                    }
                    return result + Text(segment.text)
                }
            }
            .font(.custom("IBMPlexSans-Regular", size: 13))
            .tint(Color.textSecondary)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "grove-wikilink" {
                    let title = url.host(percentEncoded: false) ?? ""
                    onWikiLinkTap?(title)
                    return .handled
                }
                return .systemAction
            })
        } else {
            if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed)
                    .font(.custom("IBMPlexSans-Regular", size: 13))
                    .tint(Color.textSecondary)
            } else {
                Text(text)
                    .font(.custom("IBMPlexSans-Regular", size: 13))
            }
        }
    }

    private struct TextSegment {
        let text: String
        let isWikiLink: Bool
    }

    private func parseWikiLinks(in text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var remaining = text[text.startIndex...]

        while let openRange = remaining.range(of: "[[") {
            let before = remaining[remaining.startIndex..<openRange.lowerBound]
            if !before.isEmpty {
                segments.append(TextSegment(text: String(before), isWikiLink: false))
            }

            let afterOpen = remaining[openRange.upperBound...]
            if let closeRange = afterOpen.range(of: "]]") {
                let linkTitle = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
                segments.append(TextSegment(text: linkTitle, isWikiLink: true))
                remaining = afterOpen[closeRange.upperBound...]
            } else {
                segments.append(TextSegment(text: String(remaining[openRange.lowerBound...]), isWikiLink: false))
                remaining = remaining[remaining.endIndex...]
            }
        }

        if !remaining.isEmpty {
            segments.append(TextSegment(text: String(remaining), isWikiLink: false))
        }

        return segments
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)

        switch level {
        case 1:
            Text(attributed)
                .font(.custom("Newsreader", size: 22))
                .fontWeight(.semibold)
                .padding(.top, 8)
        case 2:
            Text(attributed)
                .font(.custom("Newsreader", size: 18))
                .fontWeight(.medium)
                .padding(.top, 6)
        case 3:
            Text(attributed)
                .font(.custom("Newsreader", size: 16))
                .fontWeight(.medium)
                .padding(.top, 4)
        default:
            Text(attributed)
                .font(.custom("IBMPlexSans-Regular", size: 14))
                .fontWeight(.semibold)
                .padding(.top, 2)
        }
    }
}

// MARK: - Syntax Highlighted Code View

private struct SyntaxHighlightedCodeView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label
            if let lang = language, !lang.isEmpty {
                Text(lang.uppercased())
                    .font(.custom("IBMPlexMono", size: 9))
                    .fontWeight(.medium)
                    .tracking(0.8)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            // Highlighted code
            highlightedText
                .font(.custom("IBMPlexMono", size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, language != nil ? 6 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.borderPrimary, lineWidth: 1)
        )
    }

    private var highlightedText: Text {
        let tokens = tokenize(code: code, language: normalizedLanguage)
        return tokens.reduce(Text("")) { result, token in
            result + Text(token.text)
                .foregroundColor(token.color)
        }
    }

    private var normalizedLanguage: String? {
        guard let lang = language?.lowercased() else { return nil }
        switch lang {
        case "swift": return "swift"
        case "python", "py": return "python"
        case "javascript", "js", "typescript", "ts": return "javascript"
        default: return lang
        }
    }

    private struct Token {
        let text: String
        let color: Color
    }

    private func tokenize(code: String, language: String?) -> [Token] {
        guard let language else {
            return [Token(text: code, color: Color(hex: "1A1A1A"))]
        }

        let keywords: Set<String>
        let typeKeywords: Set<String>
        let builtins: Set<String>

        switch language {
        case "swift":
            keywords = ["func", "var", "let", "if", "else", "guard", "return", "import", "struct", "class", "enum", "case", "switch", "for", "while", "in", "protocol", "extension", "private", "public", "internal", "static", "self", "Self", "init", "deinit", "throw", "throws", "try", "catch", "async", "await", "actor", "some", "any", "where", "typealias", "associatedtype", "override", "final", "lazy", "weak", "unowned", "mutating", "nonmutating", "convenience", "required", "defer", "repeat", "break", "continue", "fallthrough", "do", "is", "as", "nil", "true", "false", "super"]
            typeKeywords = ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Error", "Void", "Any", "AnyObject", "Date", "UUID", "Data", "URL", "View", "State", "Binding", "Published", "Observable", "ObservedObject", "StateObject", "EnvironmentObject", "Environment"]
            builtins = ["print", "debugPrint", "fatalError", "precondition", "assert"]
        case "python":
            keywords = ["def", "class", "if", "elif", "else", "for", "while", "in", "return", "import", "from", "as", "try", "except", "finally", "raise", "with", "yield", "lambda", "pass", "break", "continue", "and", "or", "not", "is", "None", "True", "False", "del", "global", "nonlocal", "assert", "async", "await"]
            typeKeywords = ["int", "float", "str", "bool", "list", "dict", "set", "tuple", "type", "object", "bytes", "range", "Exception"]
            builtins = ["print", "len", "range", "enumerate", "zip", "map", "filter", "sorted", "reversed", "isinstance", "hasattr", "getattr", "setattr", "super", "property", "staticmethod", "classmethod", "open", "input"]
        case "javascript":
            keywords = ["function", "var", "let", "const", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "return", "throw", "try", "catch", "finally", "new", "delete", "typeof", "instanceof", "in", "of", "class", "extends", "super", "import", "export", "default", "from", "as", "async", "await", "yield", "this", "null", "undefined", "true", "false", "void"]
            typeKeywords = ["Array", "Object", "String", "Number", "Boolean", "Map", "Set", "Promise", "Symbol", "RegExp", "Error", "Date", "JSON", "Math", "console"]
            builtins = ["console", "setTimeout", "setInterval", "fetch", "require", "module", "process"]
        default:
            return [Token(text: code, color: Color(hex: "1A1A1A"))]
        }

        return highlightCode(code, keywords: keywords, typeKeywords: typeKeywords, builtins: builtins)
    }

    private func highlightCode(_ code: String, keywords: Set<String>, typeKeywords: Set<String>, builtins: Set<String>) -> [Token] {
        var tokens: [Token] = []
        var i = code.startIndex

        let defaultColor = Color(hex: "1A1A1A")
        let keywordColor = Color(hex: "6E3A8A")    // purple-ish for keywords
        let typeColor = Color(hex: "2D6A4F")        // green for types
        let stringColor = Color(hex: "9A3412")      // warm brown for strings
        let commentColor = Color(hex: "999999")      // muted for comments
        let numberColor = Color(hex: "1D4ED8")       // blue for numbers
        let builtinColor = Color(hex: "0E7490")      // teal for builtins

        while i < code.endIndex {
            let ch = code[i]

            // Line comment
            if ch == "/" && code.index(after: i) < code.endIndex && code[code.index(after: i)] == "/" {
                let start = i
                while i < code.endIndex && code[i] != "\n" {
                    i = code.index(after: i)
                }
                tokens.append(Token(text: String(code[start..<i]), color: commentColor))
                continue
            }

            // Block comment
            if ch == "/" && code.index(after: i) < code.endIndex && code[code.index(after: i)] == "*" {
                let start = i
                i = code.index(i, offsetBy: 2)
                while i < code.endIndex {
                    if code[i] == "*" && code.index(after: i) < code.endIndex && code[code.index(after: i)] == "/" {
                        i = code.index(i, offsetBy: 2)
                        break
                    }
                    i = code.index(after: i)
                }
                tokens.append(Token(text: String(code[start..<i]), color: commentColor))
                continue
            }

            // Python # comments
            if ch == "#" {
                let start = i
                while i < code.endIndex && code[i] != "\n" {
                    i = code.index(after: i)
                }
                tokens.append(Token(text: String(code[start..<i]), color: commentColor))
                continue
            }

            // Strings (double or single quote)
            if ch == "\"" || ch == "'" {
                let quote = ch
                let start = i
                i = code.index(after: i)
                while i < code.endIndex && code[i] != quote {
                    if code[i] == "\\" && code.index(after: i) < code.endIndex {
                        i = code.index(i, offsetBy: 2)
                    } else {
                        i = code.index(after: i)
                    }
                }
                if i < code.endIndex { i = code.index(after: i) }
                tokens.append(Token(text: String(code[start..<i]), color: stringColor))
                continue
            }

            // Numbers
            if ch.isNumber || (ch == "." && i < code.endIndex && code.index(after: i) < code.endIndex && code[code.index(after: i)].isNumber) {
                let start = i
                while i < code.endIndex && (code[i].isNumber || code[i] == "." || code[i] == "_") {
                    i = code.index(after: i)
                }
                tokens.append(Token(text: String(code[start..<i]), color: numberColor))
                continue
            }

            // Words (identifiers/keywords)
            if ch.isLetter || ch == "_" || ch == "@" {
                let start = i
                i = code.index(after: i)
                while i < code.endIndex && (code[i].isLetter || code[i].isNumber || code[i] == "_") {
                    i = code.index(after: i)
                }
                let word = String(code[start..<i])
                if keywords.contains(word) {
                    tokens.append(Token(text: word, color: keywordColor))
                } else if typeKeywords.contains(word) {
                    tokens.append(Token(text: word, color: typeColor))
                } else if builtins.contains(word) {
                    tokens.append(Token(text: word, color: builtinColor))
                } else if word.hasPrefix("@") {
                    tokens.append(Token(text: word, color: keywordColor))
                } else {
                    tokens.append(Token(text: word, color: defaultColor))
                }
                continue
            }

            // Whitespace and punctuation
            tokens.append(Token(text: String(ch), color: defaultColor))
            i = code.index(after: i)
        }

        return tokens
    }
}

// MARK: - Block Drop Delegate

struct BlockDropDelegate: DropDelegate {
    let targetBlock: ReflectionBlock
    let allBlocks: [ReflectionBlock]
    @Binding var draggingBlock: ReflectionBlock?
    let modelContext: ModelContext

    func performDrop(info: DropInfo) -> Bool {
        draggingBlock = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingBlock, dragging.id != targetBlock.id else { return }

        guard let fromIndex = allBlocks.firstIndex(where: { $0.id == dragging.id }),
              let toIndex = allBlocks.firstIndex(where: { $0.id == targetBlock.id }) else { return }

        if fromIndex != toIndex {
            // Reorder positions
            var reordered = allBlocks
            let moved = reordered.remove(at: fromIndex)
            reordered.insert(moved, at: toIndex)

            for (index, block) in reordered.enumerated() {
                block.position = index
            }
            try? modelContext.save()
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
