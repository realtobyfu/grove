import SwiftUI
import SwiftData
import AVKit

struct ItemReaderView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
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
    @State private var editingBlockID: UUID?
    @State private var editBlockContent = ""
    // Text selection for Reflect button
    @State private var selectedHighlightText: String?
    // Drag reordering state
    @State private var draggingBlock: ReflectionBlock?
    // Delete confirmation
    @State private var blockToDelete: ReflectionBlock?
    @State private var showDeleteConfirmation = false
    // New reflection editor sheet
    @State private var showReflectionEditor = false
    @State private var editorBlockType: ReflectionBlockType = .keyInsight
    @State private var editorContent = ""
    @State private var editorHighlight: String?
    // AI reflection prompts
    @State private var aiPrompts: [ReflectionPrompt] = []
    @State private var isLoadingPrompts = false
    @State private var dismissedPromptIDs: Set<UUID> = []
    // Inline new-reflection editor focus
    @FocusState private var isNewReflectionFocused: Bool
    // Summary editing
    @State private var isEditingSummary = false
    @State private var editableSummary = ""
    // Draggable split
    @State private var reflectionPanelWidth: CGFloat = 380

    private var sortedReflections: [ReflectionBlock] {
        item.reflections.sorted { $0.position < $1.position }
    }

    private var isVideoItem: Bool {
        item.type == .video && localVideoURL != nil
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showReflectionEditor {
                // Split mode: source left, editor right
                GeometryReader { geo in
                    let minPanel: CGFloat = 280
                    let maxPanel = max(minPanel, geo.size.width * 0.6)
                    let clampedWidth = min(max(reflectionPanelWidth, minPanel), maxPanel)

                    HStack(spacing: 0) {
                        // Left: source content
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                itemHeader

                                if let thumbnailData = item.thumbnail {
                                    CoverImageView(
                                        imageData: thumbnailData,
                                        height: 200,
                                        showPlayOverlay: false,
                                        cornerRadius: 0
                                    )
                                    .padding(.horizontal)
                                }

                                Divider().padding(.horizontal)
                                sourceContent
                                    .padding()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.bgPrimary)

                        // Draggable divider
                        Rectangle()
                            .fill(Color.borderPrimary)
                            .frame(width: 1)
                            .overlay {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 9)
                                    .contentShape(Rectangle())
                                    .onHover { hovering in
                                        if hovering {
                                            NSCursor.resizeLeftRight.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                                    .gesture(
                                        DragGesture(coordinateSpace: .global)
                                            .onChanged { value in
                                                let newWidth = geo.size.width - value.location.x
                                                reflectionPanelWidth = min(max(newWidth, minPanel), maxPanel)
                                            }
                                    )
                            }

                        // Right: editor panel
                        reflectionEditorPanel
                            .frame(width: clampedWidth)
                            .frame(maxHeight: .infinity)
                            .background(Color.bgPrimary)
                            .transition(.move(edge: .trailing))
                    }
                }
            } else {
                // Normal mode: full-width reader
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        itemHeader

                        if let thumbnailData = item.thumbnail {
                            CoverImageView(
                                imageData: thumbnailData,
                                height: 200,
                                showPlayOverlay: false,
                                cornerRadius: 0
                            )
                            .padding(.horizontal)
                        }

                        Divider().padding(.horizontal)
                        sourceContent
                            .padding()
                        Divider().padding(.horizontal)
                        reflectionsSection
                            .padding()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.bgPrimary)
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
            backfillThumbnailIfNeeded()
        }
        .onChange(of: item.id) {
            showSuggestions = false
            connectionSuggestions = []
            editingBlockID = nil
            selectedHighlightText = nil
            showReflectionEditor = false
            editorContent = ""
            editorHighlight = nil
            aiPrompts = []
            dismissedPromptIDs = []
            isLoadingPrompts = false
            isEditingSummary = false
            editableSummary = ""
            loadAIPrompts()
        }
        .sheet(isPresented: $showItemExportSheet) {
            ItemExportSheet(items: [item])
        }
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

                if item.type == .note || (item.type == .article && item.metadata["hasLLMOverview"] == "true") {
                    Button {
                        let wasEditing = isEditingContent
                        isEditingContent.toggle()
                        if wasEditing {
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

            // Review banner (shown when LLM summary/overview is pending review)
            if item.metadata["summaryReviewPending"] == "true" || item.metadata["overviewReviewPending"] == "true" {
                reviewBanner
            }

            // One-line summary display/edit
            if let summary = item.metadata["summary"], !summary.isEmpty {
                summaryField(summary: summary)
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
                Label("\(item.reflections.count) reflections", systemImage: "text.alignleft")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)

                Spacer()

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

    // MARK: - Summary Field

    private func summaryField(summary: String) -> some View {
        Group {
            if isEditingSummary {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                        TextField("One-line summary", text: $editableSummary)
                            .font(.groveBodySecondary)
                            .textFieldStyle(.plain)
                    }
                    HStack {
                        Text("\(editableSummary.count)/120")
                            .font(.groveMeta)
                            .foregroundStyle(editableSummary.count > 120 ? Color.textPrimary : Color.textTertiary)
                        Spacer()
                        Button("Done") {
                            let trimmed = editableSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                item.metadata["summary"] = String(trimmed.prefix(120))
                            }
                            isEditingSummary = false
                            try? modelContext.save()
                        }
                        .font(.groveBodySecondary)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Text(summary)
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        editableSummary = summary
                        isEditingSummary = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Edit summary")
                }
            }
        }
    }

    // MARK: - Review Banner

    private var reviewBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                Text("AI-generated summary ready for review")
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
            }

            if let summary = item.metadata["summary"], !summary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                        TextField("One-line summary", text: Binding(
                            get: { item.metadata["summary"] ?? "" },
                            set: { item.metadata["summary"] = $0 }
                        ))
                        .font(.groveBodySecondary)
                        .textFieldStyle(.plain)
                    }
                }
            }

            if item.metadata["hasLLMOverview"] == "true" {
                Text("AI overview is shown below — you can edit it with the Edit button.")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 8) {
                Button {
                    // Accept: clear review flags, keep content
                    item.metadata["summaryReviewPending"] = nil
                    item.metadata["overviewReviewPending"] = nil
                    try? modelContext.save()
                } label: {
                    Label("Accept", systemImage: "checkmark")
                        .font(.groveBodySecondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if item.metadata["overviewReviewPending"] == "true",
                   let original = item.metadata["originalDescription"], !original.isEmpty {
                    Button {
                        // Revert overview to original OG description
                        item.content = original
                        item.metadata["hasLLMOverview"] = nil
                        item.metadata["overviewReviewPending"] = nil
                        item.metadata["originalDescription"] = nil
                        try? modelContext.save()
                    } label: {
                        Label("Revert Overview", systemImage: "arrow.uturn.backward")
                            .font(.groveBodySecondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    // Dismiss: clear flags without changes
                    item.metadata["summaryReviewPending"] = nil
                    item.metadata["overviewReviewPending"] = nil
                    try? modelContext.save()
                } label: {
                    Text("Dismiss")
                        .font(.groveBodySecondary)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textTertiary)
            }
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
    }

    // MARK: - Source Content

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
        } else if isEditingContent && (item.type == .note || (item.type == .article && item.metadata["hasLLMOverview"] == "true")) {
            RichMarkdownEditor(
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
            // AI Overview label
            if item.metadata["hasLLMOverview"] == "true" {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("AI Overview")
                        .font(.groveBadge)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 4)
            }

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
                    openReflectionEditor(type: .keyInsight, content: "", highlight: highlight)
                    selectedHighlightText = nil
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

    // MARK: - Reflections Section

    private var reflectionsSection: some View {
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

                Menu {
                    ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                        Button {
                            openReflectionEditor(type: type, content: "", highlight: nil)
                        } label: {
                            Label(type.displayName, systemImage: type.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.groveBody)
                        .foregroundStyle(Color.textMuted)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
                .help("Add reflection")
            }

            Divider()

            // Always show ghost prompt buttons or AI prompts at top
            if isLoadingPrompts && sortedReflections.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating prompts...")
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.top, 4)
            }

            let visiblePrompts = aiPrompts.filter { !dismissedPromptIDs.contains($0.id) }
            if !visiblePrompts.isEmpty {
                aiPromptRows(visiblePrompts)
            } else if !isLoadingPrompts {
                ghostPrompts
            }

            // Existing reflection blocks
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
            }
        }
    }

    // MARK: - Ghost Prompts

    private var ghostPrompts: some View {
        HStack(spacing: 8) {
            ghostPromptChip(
                label: "Key claim?",
                icon: ReflectionBlockType.keyInsight.systemImage,
                blockType: .keyInsight
            )
            ghostPromptChip(
                label: "Connections?",
                icon: ReflectionBlockType.connection.systemImage,
                blockType: .connection
            )
            ghostPromptChip(
                label: "Challenge?",
                icon: ReflectionBlockType.disagreement.systemImage,
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
                    openReflectionEditor(type: prompt.suggestedBlockType, content: prompt.text, highlight: nil)
                    _ = dismissedPromptIDs.insert(prompt.id)
                }
            }
        }
    }

    private func ghostPromptChip(label: String, icon: String, blockType: ReflectionBlockType) -> some View {
        Button {
            openReflectionEditor(type: blockType, content: "", highlight: nil)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.groveMeta)
                Text(label)
                    .font(.groveBodySecondary)
            }
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        Color.borderTagDashed,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reflection Block Card

    private func reflectionBlockCard(_ block: ReflectionBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: type label + video timestamp + actions
            HStack(spacing: 6) {
                Text(block.blockType.displayName)
                    .font(.groveBadge)
                    .tracking(0.5)
                    .foregroundStyle(Color.textSecondary)

                // Video timestamp seek button
                if isVideoItem, let ts = block.videoTimestamp {
                    Button {
                        videoSeekTarget = Double(ts)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "play.circle.fill")
                                .font(.caption2)
                            Text(Double(ts).formattedTimestamp)
                                .font(.groveMeta)
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to \(Double(ts).formattedTimestamp) in video")
                }

                Spacer()

                Text(block.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)

                // Inline action buttons
                Menu {
                    ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                        Button {
                            block.blockType = type
                            try? modelContext.save()
                        } label: {
                            Label(type.displayName, systemImage: type.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: block.blockType.systemImage)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .help("Change type")

                Button {
                    editingBlockID = block.id
                    editBlockContent = block.content
                } label: {
                    Image(systemName: "pencil")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
                .help("Edit")

                Button {
                    blockToDelete = block
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
                .help("Delete")
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

    // MARK: - Reflection Editor Panel (split-pane right side)

    private var reflectionEditorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Subtle top bar: type badge (left) + close button (right)
            HStack {
                Menu {
                    ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                        Button {
                            editorBlockType = type
                        } label: {
                            Label(type.displayName, systemImage: type.systemImage)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: editorBlockType.systemImage)
                        Text(editorBlockType.displayName)
                    }
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Button { cancelReflectionEditor() } label: {
                    Image(systemName: "xmark")
                        .font(.groveBody)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
            .padding(.bottom, 8)

            // Highlight preview (if reflecting on selection) — subtle quote
            if let highlight = editorHighlight, !highlight.isEmpty {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.borderPrimary)
                        .frame(width: 2)
                    Text(highlight)
                        .font(.groveGhostText)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(3)
                        .padding(.leading, 10)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 12)
            }

            // Editor — fills remaining space, prose mode
            RichMarkdownEditor(text: $editorContent, sourceItem: item, minHeight: 200, proseMode: true)
                .focused($isNewReflectionFocused)
                .frame(maxHeight: .infinity)

            // Save bar at very bottom — minimal
            HStack {
                Spacer()
                Button("Cancel") { cancelReflectionEditor() }
                    .buttonStyle(.plain)
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                Button("Save") { saveNewReflection() }
                    .buttonStyle(.plain)
                    .font(.groveBodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(editorContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 12)
        }
    }

    private func cancelReflectionEditor() {
        withAnimation(.easeOut(duration: 0.25)) {
            showReflectionEditor = false
        }
        editorContent = ""
        editorHighlight = nil
        NotificationCenter.default.post(name: .groveExitFocusMode, object: nil)
    }

    private func saveNewReflection() {
        let trimmed = editorContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commitNewBlock(type: editorBlockType, content: trimmed, highlight: editorHighlight)
        withAnimation(.easeOut(duration: 0.25)) {
            showReflectionEditor = false
        }
        editorContent = ""
        editorHighlight = nil
        NotificationCenter.default.post(name: .groveExitFocusMode, object: nil)
    }

    // MARK: - Block Editor

    private func editBlockEditor(_ block: ReflectionBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RichMarkdownEditor(
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

    private func openReflectionEditor(type: ReflectionBlockType, content: String, highlight: String?) {
        editorBlockType = type
        editorContent = content
        editorHighlight = highlight
        withAnimation(.easeOut(duration: 0.25)) {
            showReflectionEditor = true
        }
        NotificationCenter.default.post(name: .groveEnterFocusMode, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isNewReflectionFocused = true
        }
    }

    private func commitNewBlock(type: ReflectionBlockType, content: String, highlight: String?) {
        let nextPosition = (sortedReflections.last?.position ?? -1) + 1
        let timestamp: Int? = isVideoItem ? Int(videoCurrentTime) : nil
        let block = ReflectionBlock(
            item: item,
            blockType: type,
            content: content,
            highlight: highlight,
            position: nextPosition,
            videoTimestamp: timestamp
        )
        modelContext.insert(block)
        item.reflections.append(block)
        item.updatedAt = .now
        try? modelContext.save()
    }

    private func saveEditedBlock(_ block: ReflectionBlock) {
        block.content = editBlockContent.trimmingCharacters(in: .whitespacesAndNewlines)
        item.updatedAt = .now
        try? modelContext.save()
        editingBlockID = nil
        editBlockContent = ""

        triggerSuggestions()
    }

    private func deleteBlock(_ block: ReflectionBlock) {
        item.reflections.removeAll { $0.id == block.id }
        modelContext.delete(block)
        item.updatedAt = .now
        try? modelContext.save()
    }

    // MARK: - AI Reflection Prompts

    private func loadAIPrompts() {
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

    // MARK: - Thumbnail Backfill

    /// Downloads cover image for existing items that have a thumbnailURL but no stored thumbnail.
    private func backfillThumbnailIfNeeded() {
        guard item.thumbnail == nil,
              let thumbnailURL = item.metadata["thumbnailURL"],
              !thumbnailURL.isEmpty else { return }
        Task {
            if let imageData = await ImageDownloadService.shared.downloadAndCompress(urlString: thumbnailURL) {
                item.thumbnail = imageData
                try? modelContext.save()
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
