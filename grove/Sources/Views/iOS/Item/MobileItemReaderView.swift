import SwiftUI
import SwiftData

/// Full-screen item reader for iOS.
/// Articles: displays WKWebView. Notes: navigates to MobileNoteEditorView.
/// Toolbar: back, share, "Discuss", reflections button, find-in-page.
struct MobileItemReaderView: View {
    let item: Item
    var onCloseRequested: (() -> Void)? = nil
    var preferFullScreenReaderExperience: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    // MARK: - Right panel (iPad 2-panel)

    enum RightPanel: Equatable {
        case none
        case reflections
        case chat(Conversation)

        static func == (lhs: RightPanel, rhs: RightPanel) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none): return true
            case (.reflections, .reflections): return true
            case (.chat(let a), .chat(let b)): return a.id == b.id
            default: return false
            }
        }
    }

    @State private var rightPanel: RightPanel = .none
    @State private var panelConversation: Conversation?

    @State private var dialecticsService = DialecticsService()
    @State private var showReflections = false
    @State private var showFindBar = false
    @State private var findQuery = ""
    @State private var findForwardToken = 0
    @State private var findBackwardToken = 0
    @State private var findCurrentMatch = 0
    @State private var findTotalMatches = 0
    @State private var selectedText: String?
    @State private var flashcardSession: LearningEditorSession?
    @State private var showFlashcards = false
    /// Where the selection sits in the web view's viewport, for anchoring the
    /// highlight bar next to it rather than at the bottom of the screen.
    @State private var selectionGeometry: WebSelectionGeometry?
    @State private var scrollToTextQuery = ""
    @State private var scrollToTextToken = 0
    @State private var pendingEditBlock: ReflectionBlock?
    @State private var navigateToChat: Conversation?
    @State private var reflectionDetent: PresentationDetent = .medium
    @State private var zoomLevel: CGFloat = 1.0
    @State private var sidePanelWidth: CGFloat? = LayoutSettings.width(for: .mobileReaderSidePanel)
    @FocusState private var findBarFocused: Bool

    // MARK: - In-reader browsing

    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var currentWebURL: URL?
    @State private var goBackToken = 0
    @State private var goForwardToken = 0
    /// Library item for the page currently being browsed, once it has been
    /// captured (explicitly or by writing). Reflections follow it.
    @State private var capturedPageItem: Item?
    @State private var capturedPageURL: String?
    @State private var showSavedIndicator = false
    /// Library item backing the page on screen, if any. Drives the capture
    /// FAB — nil means the page has never been saved.
    @State private var pageLibraryItem: Item?
    @State private var showCapturePicker = false
    /// Keeps the FAB on screen briefly after filing so the checkmark can
    /// confirm the action before the button retires from the page.
    @State private var showFiledConfirmation = false
    /// Held so a rapid second filing cancels the first timer instead of
    /// having it truncate the new confirmation.
    @State private var filedConfirmationTask: Task<Void, Never>? = nil

    /// True when the reader has navigated away from the item's own page. A
    /// remote video's embed stands in for its watch page, so landing on it is
    /// not browsing — nothing should offer to capture the player as a page of
    /// its own.
    private var isBrowsingLinkedPage: Bool {
        guard let currentWebURL else { return false }
        if isSameWebPage(currentWebURL, remoteVideoEmbedURL) { return false }
        return ReadingCapture.isDifferentPage(currentWebURL, from: item)
    }

    /// The item reflections and highlights belong to: the linked page once
    /// it has been captured, otherwise the item being read.
    private var readingItem: Item {
        capturedPageItem ?? item
    }

    /// Zoom and find drive the web view. A note has none, and a PDF reads in
    /// PDFKit — neither should carry controls that do nothing.
    private var showsWebPageControls: Bool {
        item.type != .note && !item.isPDFDocument
    }

    private var usesSidePanel: Bool {
        horizontalSizeClass == .regular && !preferFullScreenReaderExperience
    }

    private var isReflectionsPanelOpen: Bool { rightPanel == .reflections }
    private var isChatPanelOpen: Bool {
        if case .chat = rightPanel { return true }
        return false
    }
    private var articleURL: URL? {
        guard item.type != .note, item.metadata["videoLocalFile"] != "true" else { return nil }
        // A video hosted elsewhere loads its player, not its watch page: the
        // page is a full site, the embed is the video.
        if let embed = remoteVideoEmbedURL { return embed }
        return resolvedSourceURL(from: item.sourceURL)
    }

    /// The privacy-enhanced player for a video that isn't a local capture.
    private var remoteVideoEmbedURL: URL? {
        guard item.type == .video, item.metadata["videoLocalFile"] != "true" else { return nil }
        return VideoEmbed.remoteURL(sourceURL: item.sourceURL, metadata: item.metadata)
    }

    var body: some View {
        mainLayout
            .onAppear {
                // iPad: auto-open reflections panel for article+notes reading experience
                if usesSidePanel && rightPanel == .none {
                    rightPanel = .reflections
                }
                resolveCaptureState()
            }
            // Cached model references for the browsed page must drop before
            // the model they point at is deleted.
            .onReceive(NotificationCenter.default.publisher(for: .groveItemWillDelete)) { note in
                guard let id = NotificationCenter.itemWillDeleteID(from: note) else { return }
                if capturedPageItem?.id == id {
                    capturedPageItem = nil
                    capturedPageURL = nil
                }
                if pageLibraryItem?.id == id {
                    pageLibraryItem = nil
                    showFiledConfirmation = false
                    showCapturePicker = false
                }
            }
            .sheet(isPresented: $showCapturePicker) {
                capturePickerSheet
            }
            .navigationTitle(item.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .sheet(isPresented: $showReflections) {
                reflectionSheetContent
            }
            .sheet(item: $flashcardSession) { session in
                NavigationStack {
                    FlashcardEditorView(item: session.item, sourceQuote: session.sourceQuote)
                }
            }
            .sheet(isPresented: $showFlashcards) {
                NavigationStack { FlashcardLibraryView(itemID: readingItem.id) }
            }
            .navigationDestination(item: $navigateToChat) { conversation in
                MobileChatView(conversation: conversation)
            }
            .animation(.easeInOut(duration: 0.25), value: rightPanel)
    }

    // MARK: - Main Layout

    @ViewBuilder
    private var mainLayout: some View {
        if usesSidePanel && rightPanel != .none {
            // iPad 2-panel
            GeometryReader { geo in
                let storedOrDefaultWidth = sidePanelWidth ?? geo.size.width * 0.4
                let panelWidth = min(max(storedOrDefaultWidth, 320), 480)
                let panelWidthBinding = Binding(
                    get: { panelWidth },
                    set: { sidePanelWidth = $0 }
                )
                HStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        contentView
                        if showFindBar {
                            findBar
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ResizableTrailingDivider(
                        width: panelWidthBinding,
                        minWidth: 320,
                        maxWidth: 480,
                        onCollapse: { rightPanel = .none }
                    ) { width in
                        LayoutSettings.setWidth(width, for: .mobileReaderSidePanel)
                    }

                    rightPanelContent
                        .frame(width: panelWidthBinding.wrappedValue)
                        .frame(maxHeight: .infinity)
                        .background(Color.bgPrimary)
                }
            }
        } else {
            // iPhone or no panel open
            ZStack(alignment: .top) {
                contentView
                if showFindBar {
                    findBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Highlight actions

    private var trimmedSelection: String? {
        guard let text = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// Floats beside the selection it acts on. The overlay sits directly on the
    /// web view, so the reported viewport coordinates land in its own
    /// coordinate space with no browse-bar inset to correct for. A selection
    /// without geometry (collapsed range) keeps the old bottom placement.
    @ViewBuilder
    private var highlightActionOverlay: some View {
        if item.type != .note, let selection = trimmedSelection {
            let bar = HighlightActionBar(
                onHighlight: { addHighlight(selection) },
                onRemember: { remember(selection) }
            )
            Group {
                if let selectionGeometry {
                    SelectionAnchorLayout(geometry: selectionGeometry) { bar }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else {
                    bar
                        .padding(.bottom, Spacing.lg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: trimmedSelection != nil)
        }
    }

    private func remember(_ selection: String) {
        // Saving a question is a durable annotation, so linked pages must be
        // captured just as they are when making a highlight.
        flashcardSession = LearningEditorSession(item: resolveWritingHost(), sourceQuote: selection)
        selectedText = nil
        selectionGeometry = nil
    }

    @discardableResult
    private func addHighlight(_ text: String) -> ReflectionBlock {
        let host = resolveWritingHost()
        let nextPosition = (host.reflections.map(\.position).max() ?? -1) + 1
        let block = ReflectionBlock(
            item: host,
            blockType: .keyInsight,
            content: "",
            highlight: text,
            position: nextPosition
        )
        modelContext.insert(block)
        // Mirror ItemReaderViewModel.addHighlight: maintain the relationship and
        // bump updatedAt so highlights created on iOS sort/sync consistently.
        host.reflections.append(block)
        ReadingCapture.promoteAfterWriting(host, in: modelContext)
        host.updatedAt = .now
        try? modelContext.save()
        selectedText = nil
        selectionGeometry = nil
        return block
    }

    /// Capture-on-write: a note taken on a linked page saves that page to
    /// the library first, so the note has a durable home.
    private func resolveWritingHost() -> Item {
        if let capturedPageItem, capturedPageURL == currentWebURL?.absoluteString {
            return capturedPageItem
        }
        let resolution = ReadingCapture.host(
            for: item,
            navigatedURL: isBrowsingLinkedPage ? currentWebURL : nil,
            in: modelContext
        )
        if resolution.host.id != item.id {
            capturedPageItem = resolution.host
            capturedPageURL = currentWebURL?.absoluteString
            if resolution.didCapture {
                flashSavedIndicator()
            }
        }
        return resolution.host
    }

    private func saveCurrentPage() {
        guard let currentWebURL, isBrowsingLinkedPage else { return }
        let (captured, _) = ReadingCapture.capturePage(currentWebURL, readFrom: item, in: modelContext)
        capturedPageItem = captured
        capturedPageURL = currentWebURL.absoluteString
        flashSavedIndicator()
    }

    private func flashSavedIndicator() {
        withAnimation { showSavedIndicator = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showSavedIndicator = false }
        }
    }

    private func jumpToHighlight(_ text: String) {
        scrollToTextQuery = text
        scrollToTextToken += 1
        if !usesSidePanel {
            showReflections = false
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch item.type {
        case .note:
            MobileNoteEditorView(item: item)
        default:
            // A document reads in PDFKit rather than the web view, where
            // selection, find and reading progress are all silently inert.
            // The screen already carries its own navigation, so the panel is
            // mounted without a back-to-overview affordance of its own.
            if item.isPDFDocument {
                PDFReaderPanel(item: item)
            } else {
                articleContent
            }
        }
    }

    @ViewBuilder
    private var articleContent: some View {
        if let url = articleURL {
            #if os(iOS)
            VStack(spacing: 0) {
                if isBrowsingLinkedPage || canGoBack {
                    browseBar
                    Divider()
                }

                MobileArticleWebView(
                    url: url,
                    onTextSelected: { text in selectedText = text },
                    onSelectionGeometry: { geometry in selectionGeometry = geometry },
                    findQuery: findQuery,
                    findForwardToken: findForwardToken,
                    findBackwardToken: findBackwardToken,
                    onFindResult: { current, total in
                        findCurrentMatch = current
                        findTotalMatches = total
                    },
                    zoomLevel: zoomLevel,
                    scrollToTextQuery: scrollToTextQuery,
                    scrollToTextToken: scrollToTextToken,
                    goBackToken: goBackToken,
                    goForwardToken: goForwardToken,
                    onNavigationChanged: { back, forward, currentURL in
                        // This callback can fire synchronously from inside
                        // updateUIView (WKWebView's .url KVO fires on load).
                        // Record state only; the model write in
                        // resolveCaptureState runs from the deferred
                        // .onChange(of: currentWebURL) below.
                        canGoBack = back
                        canGoForward = forward
                        currentWebURL = currentURL
                        // A different page means any captured page item no
                        // longer applies to what's on screen.
                        if currentURL?.absoluteString != capturedPageURL {
                            capturedPageItem = nil
                            capturedPageURL = nil
                        }
                    }
                )
                .onChange(of: currentWebURL) { _, _ in
                    resolveCaptureState()
                }
                .ignoresSafeArea(edges: .bottom)
                .overlay { highlightActionOverlay }
            }
            .overlay(alignment: .bottomTrailing) { captureFAB }
            .animation(.easeInOut(duration: 0.2), value: isBrowsingLinkedPage || canGoBack)
            #else
            Text("Article view not available on this platform")
            #endif
        } else if let content = item.content, !content.isEmpty {
            // Fallback: render item content as scrollable text
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if let summary = item.metadata["summary"], !summary.isEmpty {
                        Text(summary)
                            .font(.groveBodySecondary)
                            .foregroundStyle(Color.textSecondary)
                            .italic()
                    }
                    Text(content)
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                }
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .padding(.vertical, Spacing.lg)
            }
        } else {
            ContentUnavailableView {
                Label("No Content", systemImage: "doc.text")
            } description: {
                Text("This item has no readable content.")
            }
        }
    }

    // MARK: - Capture FAB

    /// The page the capture button acts on: whatever is on screen.
    private var capturePageURL: URL? {
        currentWebURL ?? articleURL
    }

    private var captureState: ReaderCaptureState {
        guard let pageLibraryItem else { return .unsaved }
        return pageLibraryItem.boards.isEmpty ? .unfiled : .filed
    }

    @ViewBuilder
    private var captureFAB: some View {
        // A filed page carries no button — absence means "taken care of" —
        // except for a beat right after filing so the checkmark can confirm.
        if item.type != .note, let capturePageURL,
           captureState != .filed || showFiledConfirmation {
            ReaderCaptureFAB(
                state: captureState,
                pageKey: capturePageURL.absoluteString
            ) {
                handleCaptureTap()
            }
            .padding(20)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
        }
    }

    @ViewBuilder
    private var capturePickerSheet: some View {
        if let target = pageLibraryItem {
            let decision = BoardSuggestionMetadata.decision(from: target)
            BoardPickerView(
                boards: boards,
                mode: .add,
                suggestedName: decision?.suggestedName ?? "",
                recommendedBoardID: decision?.recommendedBoardID,
                alternativeBoardIDs: decision?.alternativeBoardIDs ?? [],
                onSelect: { board in
                    BoardSuggestionMetadata.recordSelection(board, on: target)
                    ItemViewModel(modelContext: modelContext).assignToBoard(target, board: board)
                    finishFiling()
                },
                onCreate: { title in
                    createAndAssignBoard(named: title, to: target)
                    finishFiling()
                }
            )
        }
    }

    /// Capture first if the page is new, then always file. A saved page is
    /// never captured twice.
    private func handleCaptureTap() {
        if pageLibraryItem == nil {
            saveCurrentPage()
            pageLibraryItem = capturedPageItem
        }
        guard pageLibraryItem != nil else { return }
        showCapturePicker = true
    }

    /// After filing: close the picker, hold the checkmark for a beat so the
    /// action reads, then let the FAB retire from the page.
    private func finishFiling() {
        resolveCaptureState()
        guard captureState == .filed else { return }
        showCapturePicker = false
        showFiledConfirmation = true
        filedConfirmationTask?.cancel()
        filedConfirmationTask = MainActorTaskScheduler.schedule(after: .milliseconds(1500)) {
            withAnimation(.easeOut(duration: 0.25)) {
                showFiledConfirmation = false
            }
        }
    }

    /// Re-resolve which library item backs the page on screen.
    private func resolveCaptureState() {
        guard item.type != .note, let capturePageURL else {
            pageLibraryItem = nil
            return
        }
        showFiledConfirmation = false
        if !isBrowsingLinkedPage {
            pageLibraryItem = item
            return
        }
        let resolved = capturedPageItem
            ?? CaptureService(modelContext: modelContext).existingItem(forURL: capturePageURL.absoluteString)
        pageLibraryItem = resolved
        // Arriving at a page that is already in the library is the same trail
        // as capturing it here would have been — record it either way.
        if let resolved {
            ReadingCapture.recordProvenance(from: item, to: resolved, in: modelContext)
        }
    }

    private func createAndAssignBoard(named rawTitle: String, to target: Item) {
        let title = BoardSuggestionEngine.cleanedBoardName(rawTitle)
        guard !title.isEmpty else { return }

        let itemViewModel = ItemViewModel(modelContext: modelContext)
        if let existing = boards.first(where: {
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        }) {
            BoardSuggestionMetadata.recordSelection(existing, on: target)
            itemViewModel.assignToBoard(target, board: existing)
        } else {
            let board = Board(title: title)
            modelContext.insert(board)
            BoardSuggestionMetadata.recordSelection(board, on: target)
            itemViewModel.assignToBoard(target, board: board)
        }
    }

    // MARK: - Browse bar

    /// Appears once reading leaves the item's own page: history controls,
    /// the current domain, and a save action for the page on screen.
    private var browseBar: some View {
        HStack(spacing: Spacing.md) {
            Button {
                goBackToken += 1
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(canGoBack ? Color.textSecondary : Color.textMuted)
                    .frame(width: LayoutDimensions.minTouchTarget, height: LayoutDimensions.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .accessibilityLabel("Back")

            Button {
                goForwardToken += 1
            } label: {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(canGoForward ? Color.textSecondary : Color.textMuted)
                    .frame(width: LayoutDimensions.minTouchTarget, height: LayoutDimensions.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .accessibilityLabel("Forward")

            Text(currentWebURL?.host(percentEncoded: false) ?? "")
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: Spacing.sm)

            if showSavedIndicator {
                Label("Saved", systemImage: "checkmark.circle")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, LayoutDimensions.contentPaddingH)
        .frame(height: LayoutDimensions.minTouchTarget)
        .background(Color.bgCard)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let onCloseRequested {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    onCloseRequested()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("New flashcard", systemImage: "plus.rectangle.on.rectangle") {
                    flashcardSession = LearningEditorSession(item: resolveWritingHost(), sourceQuote: trimmedSelection)
                }
                Button("Manage flashcards", systemImage: "rectangle.on.rectangle") { showFlashcards = true }
            } label: {
                Label("Flashcards", systemImage: "rectangle.on.rectangle")
            }
            .accessibilityLabel("Flashcards")
            // Zoom controls (articles only)
            if showsWebPageControls {
                Menu {
                    Button { zoomLevel = min(zoomLevel + 0.1, 2.0) } label: {
                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                    }
                    .disabled(zoomLevel >= 2.0)

                    Button { zoomLevel = max(zoomLevel - 0.1, 0.5) } label: {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    .disabled(zoomLevel <= 0.5)

                    Divider()

                    Button { zoomLevel = 1.0 } label: {
                        Label("Reset (\(Int(round(zoomLevel * 100)))%)", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(zoomLevel == 1.0)
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel("Zoom")
            }

            // Find in page (articles only)
            if showsWebPageControls {
                Button {
                    withAnimation { showFindBar.toggle() }
                    if showFindBar { findBarFocused = true }
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel("Find in page")
            }

            // Reflections button
            Button {
                if usesSidePanel {
                    // iPad: toggle side panel
                    withAnimation {
                        rightPanel = isReflectionsPanelOpen ? .none : .reflections
                    }
                } else {
                    // iPhone: open sheet
                    if horizontalSizeClass == .regular {
                        reflectionDetent = .large
                    }
                    showReflections = true
                }
            } label: {
                Image(systemName: isReflectionsPanelOpen ? "text.bubble.fill" : "text.bubble")
            }
            .accessibilityLabel("Reflections")

            // Chat button
            Button {
                if usesSidePanel {
                    // iPad: toggle side panel
                    if isChatPanelOpen {
                        withAnimation { rightPanel = .none }
                    } else {
                        startDiscussionForPanel()
                    }
                } else {
                    // iPhone: navigate push
                    startDiscussion()
                }
            } label: {
                Image(systemName: isChatPanelOpen ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
            }
            .accessibilityLabel("Discuss")

            #if os(iOS)
            // Share
            ShareLink(item: shareURL) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share")
            #endif
        }
    }

    private var shareURL: URL {
        if let url = articleURL {
            return url
        }
        return URL(string: "grove://item/\(item.id.uuidString)")!
    }

    // MARK: - Find bar

    private var findBar: some View {
        HStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textMuted)
                TextField("Find in page", text: $findQuery)
                    .font(.groveBody)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .focused($findBarFocused)
                    .onSubmit { findForwardToken += 1 }

                if !findQuery.isEmpty {
                    Text("\(findCurrentMatch)/\(findTotalMatches)")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 8)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                findBackwardToken += 1
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(findTotalMatches == 0)

            Button {
                findForwardToken += 1
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(findTotalMatches == 0)

            Button("Done") {
                withAnimation {
                    showFindBar = false
                    findQuery = ""
                    findBarFocused = false
                }
            }
            .font(.groveBody)
        }
        .padding(.horizontal, LayoutDimensions.contentPaddingH)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Reflections sheet

    @ViewBuilder
    private var reflectionSheetContent: some View {
        let isRegular = horizontalSizeClass == .regular
        MobileReflectionSheet(
            item: readingItem,
            requestedEditBlock: $pendingEditBlock,
            onHighlightTap: articleURL != nil ? { jumpToHighlight($0) } : nil
        )
        .frame(minWidth: isRegular ? 400 : nil)
        #if os(iOS)
        .presentationDetents(isRegular ? [.large] : [.medium, .large], selection: $reflectionDetent)
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Right panel content (iPad)

    @ViewBuilder
    private var rightPanelContent: some View {
        switch rightPanel {
        case .none:
            EmptyView()
        case .reflections:
            MobileReflectionSheet(
                item: readingItem,
                onDismiss: {
                    withAnimation { rightPanel = .none }
                },
                requestedEditBlock: $pendingEditBlock,
                onHighlightTap: articleURL != nil ? { jumpToHighlight($0) } : nil
            )
        case .chat(let conversation):
            NavigationStack {
                MobileChatView(conversation: conversation)
            }
        }
    }

    // MARK: - Actions

    private func startDiscussionForPanel() {
        // Reuse existing panel conversation if it belongs to this item
        if let existing = panelConversation,
           existing.seedItemIDs.contains(item.id) {
            withAnimation { rightPanel = .chat(existing) }
            return
        }
        let conversation = dialecticsService.startConversation(
            trigger: .userInitiated,
            seedItems: [item],
            board: item.boards.first,
            context: modelContext
        )
        Task {
            _ = await dialecticsService.sendMessage(
                userText: "Let's discuss \"\(item.title)\".",
                conversation: conversation,
                context: modelContext
            )
        }
        panelConversation = conversation
        withAnimation { rightPanel = .chat(conversation) }
    }

    private func startDiscussion() {
        let conversation = dialecticsService.startConversation(
            trigger: .userInitiated,
            seedItems: [item],
            board: item.boards.first,
            context: modelContext
        )
        // Send an opening message about the item
        Task {
            _ = await dialecticsService.sendMessage(
                userText: "Let's discuss \"\(item.title)\".",
                conversation: conversation,
                context: modelContext
            )
        }
        navigateToChat = conversation
    }
}
