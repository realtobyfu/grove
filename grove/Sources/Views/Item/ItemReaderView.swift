import SwiftUI
import SwiftData
import AVKit

struct ItemReaderView: View {
    @Bindable var item: Item
    @Binding var isWebViewActive: Bool
    var alwaysShowReflectionPanel: Bool = false
    var onNavigateToItem: ((Item) -> Void)?
    @Environment(\.modelContext) private var modelContext

    // ViewModel created lazily per item
    @State private var vm: ItemReaderViewModel?

    // Pure UI state (stays in the View)
    @State private var draggingBlock: ReflectionBlock?
    @State private var showDeleteConfirmation = false
    @FocusState private var isNewReflectionFocused: Bool

    private var viewModel: ItemReaderViewModel {
        if let vm, vm.item.id == item.id { return vm }
        let newVM = ItemReaderViewModel(item: item, modelContext: modelContext, onNavigateToItem: onNavigateToItem)
        Task { @MainActor in self.vm = newVM }
        return newVM
    }

    var body: some View {
        let vm = viewModel
        ZStack(alignment: .topTrailing) {
            // The web pane renders in ONE structural position regardless of
            // whether the reflections rail is up — the rail collapses to
            // .hidden instead of the layout switching branches. A branch flip
            // here would give the panel a fresh identity and wipe its web
            // navigation state mid-highlight.
            if vm.showArticleWebView, let url = vm.articleURL {
                webSplitLayout(vm: vm, url: url)
            } else if shouldShowSplitLayout(vm) {
                splitLayout(vm: vm)
            } else {
                singleColumnLayout(vm: vm)
            }
        }
        .overlay(alignment: .bottom) {
            // Native-content highlight actions. The web panel shows its own
            // bar internally, so this only covers non-web selections.
            if !vm.showArticleWebView, let selection = vm.highlightableSelection {
                HighlightActionBarOverlay(vm: vm, selection: selection, focusTrigger: focusReflectionEditor)
            }
        }
        .animation(.easeOut(duration: 0.15), value: !vm.showArticleWebView && vm.highlightableSelection != nil)
        .onAppear {
            vm.backfillThumbnailIfNeeded()
            openWebViewForNewsletterIssueIfNeeded(vm)
        }
        .onChange(of: item.id) {
            openWebViewForNewsletterIssueIfNeeded(vm)
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveOpenReflectMode)) { _ in
            vm.toggleReflectionEditor(focusTrigger: focusReflectionEditor)
        }
        .onChange(of: item.id) {
            vm.resetOnItemChange()
        }
        .onChange(of: vm.showArticleWebView) {
            isWebViewActive = vm.showArticleWebView
            if !vm.showArticleWebView { vm.closeFindBar() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveFindInArticle)) { _ in
            vm.showFindBar.toggle()
            if !vm.showFindBar { vm.closeFindBar() }
        }
        .alert("Delete Reflection Block?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                vm.cancelDeleteBlock()
            }
            Button("Delete", role: .destructive) {
                vm.confirmDeleteBlock()
            }
        } message: {
            Text("This reflection block will be permanently removed.")
        }
        .onChange(of: vm.blockToDelete != nil) { _, hasBlock in
            if hasBlock { showDeleteConfirmation = true }
        }
    }

    private func shouldShowSplitLayout(_ vm: ItemReaderViewModel) -> Bool {
        let panelIsNeeded = alwaysShowReflectionPanel || !vm.sortedReflections.isEmpty || vm.showReflectionEditor
        return panelIsNeeded && !vm.isReflectionPanelCollapsed
    }

    // MARK: - Web Split Layout (web pane + optional rail, one identity)

    /// Hosts the web pane beside the rail. The pane is ALWAYS at the same
    /// structural position; when no reflections exist and no editor is open
    /// the rail mode is .hidden (0pt) rather than a different layout branch,
    /// so highlighting from the web pane never remounts it.
    @ViewBuilder
    private func webSplitLayout(vm: ItemReaderViewModel, url: URL) -> some View {
        GeometryReader { geo in
            let railMode: RightRailMode = shouldShowSplitLayout(vm)
                ? (vm.showReflectionEditor ? .reflectionEditor : .reflections)
                : .hidden

            HStack(spacing: 0) {
                ItemReaderWebViewPanel(vm: vm, url: url, focusTrigger: focusReflectionEditor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bgPrimary)

                RightRailContainer(
                    mode: railMode,
                    availableWidth: geo.size.width,
                    onCollapse: {
                        if vm.showReflectionEditor {
                            vm.closeReflectionEditor()
                        }
                        vm.isReflectionPanelCollapsed = true
                    }
                ) { mode in
                    switch mode {
                    case .reflectionEditor:
                        reflectionEditorPanel(vm: vm)
                    case .reflections:
                        ReflectionsListPanel(vm: vm, draggingBlock: $draggingBlock, focusTrigger: focusReflectionEditor)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxHeight: .infinity)
                .background(Color.bgPrimary)
            }
        }
    }

    // MARK: - Split Layout (Modes B and C)

    @ViewBuilder
    private func splitLayout(vm: ItemReaderViewModel) -> some View {
        GeometryReader { geo in
            // Reflections list and reflection editor are two modes of the one
            // rail, at one width — the swap is a crossfade, not a resize, so
            // the article never re-wraps for it and there is no blank frame
            // between the old panel leaving and the new one arriving.
            let railMode: RightRailMode = vm.showReflectionEditor ? .reflectionEditor : .reflections

            HStack(spacing: 0) {
                ScrollView {
                    // Fixed measure, flexible gutters: a rail width
                    // change is absorbed either side of the text
                    // instead of re-flowing it.
                    ReaderMeasureColumn {
                        VStack(alignment: .leading, spacing: 0) {
                            ItemReaderHeaderView(vm: vm, onExport: { ItemExportAction.exportAsMarkdown(item) })
                            coverImage(vm: vm)
                            Divider().padding(.horizontal)
                            sourceContent(vm: vm).padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgPrimary)

                RightRailContainer(
                    mode: railMode,
                    availableWidth: geo.size.width,
                    onCollapse: {
                        if vm.showReflectionEditor {
                            vm.closeReflectionEditor()
                        }
                        vm.isReflectionPanelCollapsed = true
                    }
                ) { mode in
                    switch mode {
                    case .reflectionEditor:
                        reflectionEditorPanel(vm: vm)
                    case .reflections:
                        ReflectionsListPanel(vm: vm, draggingBlock: $draggingBlock, focusTrigger: focusReflectionEditor)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxHeight: .infinity)
                .background(Color.bgPrimary)
            }
        }
    }

    // MARK: - Single Column Layout (Mode A)

    @ViewBuilder
    private func singleColumnLayout(vm: ItemReaderViewModel) -> some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ItemReaderHeaderView(vm: vm, onExport: { ItemExportAction.exportAsMarkdown(item) })
                    coverImage(vm: vm)
                    Divider().padding(.horizontal)
                    sourceContent(vm: vm).padding()
                    Divider().padding(.horizontal)
                    if vm.isReflectionPanelCollapsed && !vm.sortedReflections.isEmpty {
                        InlineReflectionsSection(
                            vm: vm,
                            draggingBlock: $draggingBlock,
                            focusTrigger: focusReflectionEditor,
                            showExpandButton: true
                        )
                        .padding()
                    } else if vm.sortedReflections.isEmpty {
                        InlineReflectionsSection(
                            vm: vm,
                            draggingBlock: $draggingBlock,
                            focusTrigger: focusReflectionEditor
                        )
                        .padding()
                    }
                }
                .frame(width: geo.size.width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.bgPrimary)
    }

    // MARK: - Cover Image

    @ViewBuilder
    private func coverImage(vm: ItemReaderViewModel) -> some View {
        if let thumbnailData = vm.item.thumbnail {
            CoverImageView(
                imageData: thumbnailData,
                height: 200,
                showPlayOverlay: false,
                cornerRadius: 0,
                contentMode: vm.item.type == .article ? .fit : .fill
            )
            .padding(.horizontal)
            .onTapGesture {
                if vm.articleURL != nil {
                    withAnimation(.easeOut(duration: 0.2)) {
                        vm.showArticleWebView = true
                    }
                }
            }
        }
    }

    // MARK: - Source Content

    @ViewBuilder
    private func sourceContent(vm: ItemReaderViewModel) -> some View {
        if vm.item.type == .video, let videoURL = vm.localVideoURL {
            VStack(spacing: 8) {
                VideoPlayerView(
                    url: videoURL,
                    currentTime: Binding(get: { vm.videoCurrentTime }, set: { vm.videoCurrentTime = $0 }),
                    duration: Binding(get: { vm.videoDuration }, set: { vm.videoDuration = $0 }),
                    seekToTime: vm.videoSeekTarget
                )
                .frame(minHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text(vm.videoCurrentTime.formattedTimestamp)
                        .font(.groveMeta)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                    Text("/")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                    Text(vm.videoDuration.formattedTimestamp)
                        .font(.groveMeta)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    if let path = vm.item.metadata["originalPath"] {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                }

                if let content = vm.item.content, !content.isEmpty {
                    Divider()
                    SelectableMarkdownView(markdown: content, onSelectText: { vm.webSelectedText = $0 })
                }
            }
        } else if vm.isEditingContent && (vm.item.type == .note || (vm.item.type == .article && vm.item.metadata["hasLLMOverview"] == "true")) {
            RichMarkdownEditor(
                text: Binding(
                    get: { vm.item.content ?? "" },
                    set: {
                        vm.item.content = $0.isEmpty ? nil : $0
                        vm.item.updatedAt = .now
                    }
                ),
                sourceItem: vm.item,
                minHeight: 200
            )
        } else if let content = vm.item.content, !content.isEmpty {
            if vm.item.metadata["hasLLMOverview"] == "true" {
                AIOverviewHeaderRow(vm: vm)
                    .padding(.bottom, 4)
            }

            SelectableMarkdownView(markdown: content, onSelectText: { vm.webSelectedText = $0 })
        } else {
            Text("No content available.")
                .font(.groveBody)
                .foregroundStyle(Color.textTertiary)
                .italic()
        }
    }

    // MARK: - Reflection Editor Panel (Mode C)

    @ViewBuilder
    private func reflectionEditorPanel(vm: ItemReaderViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let block = vm.editingBlock {
                // Subtle top bar: type badge (left) + close button (right)
                HStack {
                    Menu {
                        ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                            Button {
                                block.blockType = type
                                vm.item.updatedAt = .now
                            } label: {
                                Label(type.displayName, systemImage: type.systemImage)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: block.blockType.systemImage)
                            Text(block.blockType.displayName)
                        }
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer()

                    Button { vm.closeReflectionEditor() } label: {
                        Image(systemName: "xmark")
                            .font(.groveBody)
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.leading, 24)
                .padding(.trailing, 12)
                .padding(.top, 20)
                .padding(.bottom, 8)

                // Highlight preview (if reflecting on selection)
                if let highlight = block.highlight, !highlight.isEmpty {
                    HighlightQuoteChip(
                        quote: highlight,
                        kicker: vm.articleURL != nil ? "From article" : "From source",
                        onJump: vm.articleURL != nil ? { vm.jumpToHighlight(highlight) } : nil
                    )
                    .padding(.horizontal, 40)
                    .padding(.bottom, 10)
                }

                // Editor -- fills remaining space
                RichMarkdownEditor(
                    text: Binding(
                        get: { block.content },
                        set: {
                            block.content = $0
                            vm.item.updatedAt = .now
                        }
                    ),
                    sourceItem: vm.item,
                    minHeight: 200,
                    proseMode: true
                )
                .focused($isNewReflectionFocused)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    // MARK: - Focus Helper

    /// Newsletter issues carry no local body (the feed description is just
    /// an excerpt), so the reader goes straight to the real page.
    private func openWebViewForNewsletterIssueIfNeeded(_ vm: ItemReaderViewModel) {
        guard item.isNewsletterIssue,
              (item.content ?? "").isEmpty,
              vm.articleURL != nil,
              !vm.showArticleWebView else { return }
        vm.showArticleWebView = true
    }

    private func focusReflectionEditor() {
        isNewReflectionFocused = true
    }

    // MARK: - Selection Helper

    /// Non-empty trimmed native-content selection, or nil.
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
