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
    @State private var reflectionPanelWidth: CGFloat? = LayoutSettings.width(for: .readerReflections)
    @State private var showItemExportSheet = false
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
            if shouldShowSplitLayout(vm) {
                splitLayout(vm: vm)
            } else if vm.showArticleWebView, let url = vm.articleURL {
                ItemReaderWebViewPanel(vm: vm, url: url, focusTrigger: focusReflectionEditor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bgPrimary)
            } else {
                singleColumnLayout(vm: vm)
            }
        }
        .onAppear {
            vm.backfillThumbnailIfNeeded()
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
        .sheet(isPresented: $showItemExportSheet) {
            ItemExportSheet(item: item)
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

    // MARK: - Split Layout (Modes B and C)

    @ViewBuilder
    private func splitLayout(vm: ItemReaderViewModel) -> some View {
        GeometryReader { geo in
            let minPanel: CGFloat = 280
            let maxPanel = max(minPanel, geo.size.width * 0.72)
            let storedOrDefaultWidth = reflectionPanelWidth ?? geo.size.width * 0.45
            let clampedWidth = min(max(storedOrDefaultWidth, minPanel), maxPanel)
            let panelWidthBinding = Binding(
                get: { clampedWidth },
                set: { reflectionPanelWidth = $0 }
            )

            HStack(spacing: 0) {
                // Left: article WebView OR scrollable content
                Group {
                    if vm.showArticleWebView, let url = vm.articleURL {
                        ItemReaderWebViewPanel(vm: vm, url: url, focusTrigger: focusReflectionEditor)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ItemReaderHeaderView(vm: vm, showItemExportSheet: $showItemExportSheet)
                                coverImage(vm: vm)
                                Divider().padding(.horizontal)
                                sourceContent(vm: vm).padding()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgPrimary)

                // Draggable divider
                ResizableTrailingDivider(
                    width: panelWidthBinding,
                    minWidth: minPanel,
                    maxWidth: maxPanel,
                    onCollapse: {
                        if vm.showReflectionEditor {
                            vm.closeReflectionEditor()
                        }
                        vm.isReflectionPanelCollapsed = true
                    }
                ) { width in
                    LayoutSettings.setWidth(width, for: .readerReflections)
                }

                // Right: swap between reflections list (Mode B) and editor (Mode C)
                Group {
                    if vm.showReflectionEditor {
                        reflectionEditorPanel(vm: vm)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    } else {
                        ReflectionsListPanel(vm: vm, draggingBlock: $draggingBlock, focusTrigger: focusReflectionEditor)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
                }
                .animation(.easeOut(duration: 0.25), value: vm.showReflectionEditor)
                .frame(width: panelWidthBinding.wrappedValue)
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
                    ItemReaderHeaderView(vm: vm, showItemExportSheet: $showItemExportSheet)
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
                    SelectableMarkdownView(markdown: content)
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
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("AI Overview")
                        .font(.groveBadge)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 4)
            }

            SelectableMarkdownView(markdown: content)
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
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Focus Helper

    private func focusReflectionEditor() {
        isNewReflectionFocused = true
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
