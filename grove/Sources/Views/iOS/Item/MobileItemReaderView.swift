import SwiftUI
import SwiftData
import WebKit

/// Full-screen item reader for iOS.
/// Articles: Reader mode (Grove's own template over a Readability extraction)
/// when the page extracts, the live page otherwise or on request.
/// Notes: navigates to MobileNoteEditorView.
/// Toolbar: back, Reader | Live, Reflections, and (iPhone) an overflow menu
/// with Info, Discuss, Share, Find, Text size and Flashcards. iPad has room
/// for every action directly.
///
/// This is the compact-width reader: iPhone, and iPad in compact width (Slide
/// Over, narrow split). Reflections and Discuss open as a sheet and a push. A
/// regular-width iPad reads in `IPadItemReaderHostView` instead.
struct MobileItemReaderView: View {
    let item: Item
    var onCloseRequested: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    // Reader typography — the same app-wide keys and defaults as the macOS
    // reader, so a size or typeface chosen on one surface holds on the other.
    @AppStorage(ReaderTypographySettings.sizeStepKey) private var readerSizeStep = ReaderTypographySettings.defaultSizeStep
    @AppStorage(ReaderTypographySettings.isWideKey) private var readerIsWide = false
    @AppStorage(ReaderTypographySettings.useSerifKey) private var readerUseSerif = true

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
    @FocusState private var findBarFocused: Bool

    // MARK: - Info

    /// Info is a sheet with detents on iPhone and a popover from its toolbar
    /// button on iPad. Separate flags, so neither presentation can fire in
    /// the other's layout.
    @State private var showInfoSheet = false
    @State private var showInfoPopover = false
    /// A connected item opened from Info, pushed onto this stack.
    @State private var navigateToLinkedItem: Item?

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

    // MARK: - Reader mode

    /// The item's extracted article (disk cache or a fresh extraction).
    @State private var readerArticle: ReadableArticle?
    /// False until the disk cache has been consulted. The article pane waits
    /// one beat for it so an item with a cached article opens straight into
    /// Reader without fetching the live page at all.
    @State private var readerCacheChecked = false
    /// Extraction runs at most once per visit, like the macOS reader.
    @State private var readerExtractionAttempted = false
    /// The standing Reader | Live choice for this item. Reader is the default
    /// whenever an article exists; choosing Live is remembered per item.
    @State private var prefersReaderMode = true
    /// True once the live page has been on screen. It then stays mounted,
    /// hidden, behind Reader so toggling keeps its history and position.
    @State private var hasMountedLiveView = false
    /// In-place navigation request for the live page (a link tapped in Reader).
    @State private var pendingNavigationURL: URL?
    @State private var navigationToken = 0
    /// Bumped to drop Reader's text selection once it has been acted on.
    @State private var clearSelectionToken = 0
    @State private var lastSavedReadingProgress: Double = -1

    /// True when the reader has navigated away from the item's own page. A
    /// remote video's embed stands in for its watch page, so landing on it is
    /// not browsing — nothing should offer to capture the player as a page of
    /// its own. Likewise the page the Reader article was extracted from (a
    /// canonical redirect of the item's URL) is the item's own page.
    private var isBrowsingLinkedPage: Bool {
        guard let currentWebURL else { return false }
        if isSameWebPage(currentWebURL, remoteVideoEmbedURL) { return false }
        if let extractedFrom = readerArticle?.sourceURLString.flatMap(URL.init(string:)),
           isSameWebPage(currentWebURL, extractedFrom) {
            return false
        }
        return ReadingCapture.isDifferentPage(currentWebURL, from: item)
    }

    /// Reader mode is for articles read on the web: not notes, PDFs (PDFKit),
    /// videos (no prose to extract) or anything without a page to load.
    private var supportsReaderMode: Bool {
        item.type == .article && !item.isPDFDocument && articleURL != nil
    }

    /// What is on screen, never only what was asked for: a followed link is
    /// shown live, and Reader returns by itself back on the item's own page.
    private var showsReaderContent: Bool {
        supportsReaderMode && prefersReaderMode && readerArticle != nil && !isBrowsingLinkedPage
    }

    /// The toggle works only where there is a Reader view of the page on
    /// screen: never before extraction succeeds, never on a followed link.
    private var canToggleReaderMode: Bool {
        readerArticle != nil && !isBrowsingLinkedPage
    }

    private var readerTypography: ReaderTypographySettings {
        ReaderTypographySettings(sizeStep: readerSizeStep, isWide: readerIsWide, useSerif: readerUseSerif)
    }

    /// Saved highlights for the item, rendered as marks in Reader.
    private var readerHighlights: [String] {
        item.reflections
            .sorted { $0.position < $1.position }
            .compactMap { block in
                let quote = (block.highlight ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return quote.isEmpty ? nil : quote
            }
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

    private var articleURL: URL? {
        guard item.type != .note, !item.isVideoLocalFile else { return nil }
        // A video hosted elsewhere loads its player, not its watch page: the
        // page is a full site, the embed is the video.
        if let embed = remoteVideoEmbedURL { return embed }
        return resolvedSourceURL(from: item.sourceURL)
    }

    /// The privacy-enhanced player for a video that isn't a local capture.
    private var remoteVideoEmbedURL: URL? {
        guard item.type == .video, !item.isVideoLocalFile else { return nil }
        return VideoEmbed.remoteURL(sourceURL: item.sourceURL, videoSource: item.videoSource, videoID: item.videoID)
    }

    var body: some View {
        mainLayout
            .onAppear {
                resolveCaptureState()
            }
            .task(id: item.id) {
                await loadCachedReaderArticle()
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
            .sheet(isPresented: $showInfoSheet) {
                infoSheetContent
            }
            .navigationDestination(item: $navigateToChat) { conversation in
                MobileChatView(conversation: conversation)
            }
            .navigationDestination(item: $navigateToLinkedItem) { linkedItem in
                MobileItemReaderView(item: linkedItem)
            }
    }

    // MARK: - Main Layout

    private var mainLayout: some View {
        ZStack(alignment: .top) {
            contentView
            if showFindBar {
                findBar
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
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
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
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
        clearSelectionToken += 1
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
        // In Reader the new highlight string is marked on the next render
        // pass; dropping the page selection keeps the bar from re-anchoring
        // to text that is already a highlight.
        selectedText = nil
        selectionGeometry = nil
        clearSelectionToken += 1
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
        withAnimation(reduceMotion ? nil : .default) { showSavedIndicator = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(reduceMotion ? nil : .default) { showSavedIndicator = false }
        }
    }

    private func jumpToHighlight(_ text: String) {
        scrollToTextQuery = text
        scrollToTextToken += 1
        showReflections = false
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
            if supportsReaderMode && !readerCacheChecked {
                // One beat while the reader cache is read; see readerCacheChecked.
                Color.bgPrimary
                    .ignoresSafeArea(edges: .bottom)
            } else {
                VStack(spacing: 0) {
                    // History controls belong to the live page. Reader is the
                    // item's own article, so it reads without the strip.
                    if showsBrowseBar {
                        browseBar
                        Divider()
                    }

                    ZStack {
                        // The live page stays mounted underneath Reader once
                        // it has been shown, so its history and scroll
                        // position survive toggling (as on macOS).
                        if !showsReaderContent || hasMountedLiveView {
                            liveWebView(url: url)
                                .opacity(showsReaderContent ? 0 : 1)
                                .allowsHitTesting(!showsReaderContent)
                                .accessibilityHidden(showsReaderContent)
                                .onAppear { hasMountedLiveView = true }
                        }

                        if showsReaderContent, let readerArticle {
                            readerWebView(article: readerArticle)
                                .transition(.opacity)
                        }
                    }
                    .onChange(of: currentWebURL) { _, _ in
                        // Any move of the live page means a pending link
                        // navigation has been consumed; don't replay it if the
                        // web view is ever rebuilt.
                        pendingNavigationURL = nil
                        resolveCaptureState()
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .overlay { highlightActionOverlay }
                }
                .overlay(alignment: .bottomTrailing) { captureFAB }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsBrowseBar)
                .animation(.easeOut(duration: 0.2), value: showsReaderContent)
            }
            #else
            Text("Article view not available on this platform")
            #endif
        } else if let content = item.content, !content.isEmpty {
            // Fallback: render item content as scrollable text
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.groveBodySecondary)
                            .foregroundStyle(Color.textSecondary)
                            .italic()
                    }
                    if let overview = item.overview, !overview.isEmpty {
                        ItemCollapsibleTextBlock(label: "AI Overview", text: overview)
                    }
                    Text(content)
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                }
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .padding(.vertical, Spacing.lg)
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Nothing to read here.")
                    .font(.groveListTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("This item has no readable content.")
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.top, Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Web panes

    private var showsBrowseBar: Bool {
        !showsReaderContent && (isBrowsingLinkedPage || canGoBack)
    }

    /// The live page. Find, zoom and its find results are routed here only
    /// while it is the pane on screen; hidden behind Reader it gets an empty
    /// query, which clears its marks without reporting over Reader's counts.
    #if os(iOS)
    private func liveWebView(url: URL) -> some View {
        let isOnScreen = !showsReaderContent
        return MobileArticleWebView(
            url: url,
            onTextSelected: { text in selectedText = text },
            onSelectionGeometry: { geometry in selectionGeometry = geometry },
            findQuery: isOnScreen ? findQuery : "",
            findForwardToken: findForwardToken,
            findBackwardToken: findBackwardToken,
            onFindResult: isOnScreen ? { current, total in
                findCurrentMatch = current
                findTotalMatches = total
            } : nil,
            zoomLevel: zoomLevel,
            scrollToTextQuery: scrollToTextQuery,
            scrollToTextToken: scrollToTextToken,
            goBackToken: goBackToken,
            goForwardToken: goForwardToken,
            navigateURL: pendingNavigationURL,
            navigateToken: navigationToken,
            onNavigationChanged: { back, forward, currentURL in
                // This callback can fire synchronously from inside
                // updateUIView (WKWebView's .url KVO fires on load).
                // Record state only; the model write in
                // resolveCaptureState runs from the deferred
                // .onChange(of: currentWebURL) on the pane.
                canGoBack = back
                canGoForward = forward
                currentWebURL = currentURL
                // A different page means any captured page item no
                // longer applies to what's on screen.
                if currentURL?.absoluteString != capturedPageURL {
                    capturedPageItem = nil
                    capturedPageURL = nil
                }
            },
            onPageFinished: { webView in
                handleLivePageDidFinish(webView)
            }
        )
    }

    /// Grove's reader template over the extracted article: saved highlights
    /// as marks, the shared selection reporter feeding the same highlight bar,
    /// scroll-to-text from reflection chips, and find through the find bar.
    private func readerWebView(article: ReadableArticle) -> some View {
        ReaderModeWebView(
            article: article,
            typography: readerTypography,
            isDark: colorScheme == .dark,
            initialProgress: item.readingProgress,
            scrollToTextQuery: scrollToTextQuery,
            scrollToTextToken: scrollToTextToken,
            highlights: readerHighlights,
            findQuery: findQuery,
            findForwardToken: findForwardToken,
            findBackwardToken: findBackwardToken,
            onFindResult: { current, total in
                findCurrentMatch = current
                findTotalMatches = total
            },
            clearSelectionToken: clearSelectionToken,
            onTextSelected: { text in selectedText = text },
            onSelectionGeometry: { geometry in selectionGeometry = geometry },
            onScrollProgress: { fraction in updateReadingProgress(fraction) },
            onOpenExternalLink: { link in openLinkFromReader(link) }
        )
    }
    #endif

    // MARK: - Reader mode actions

    /// Reads the item's cached extraction off the main thread and settles the
    /// per-item Reader | Live choice before the article pane mounts anything.
    private func loadCachedReaderArticle() async {
        guard !readerCacheChecked else { return }
        if supportsReaderMode {
            prefersReaderMode = !ReaderModePreference.prefersLive(item.id)
            let itemID = item.id
            let service = ArticleReaderService.shared
            let cached = await Task.detached(priority: .userInitiated) {
                service.cachedArticle(for: itemID)
            }.value
            if let cached {
                readerArticle = cached
                if item.readTimeMinutes == nil {
                    item.readTimeMinutes = cached.readMinutes
                }
            }
        }
        readerCacheChecked = true
    }

    /// The live page finished a load: run Readability once per visit on the
    /// item's own article, cache the result, and let Reader take over (unless
    /// Live is this item's standing choice). A page that won't parse stays
    /// live with the toggle disabled — no error, no empty reader.
    private func handleLivePageDidFinish(_ webView: WKWebView) {
        guard supportsReaderMode, readerArticle == nil, !readerExtractionAttempted else { return }
        // Only this item's article — not a consent interstitial or redirect
        // shell on another host — may be cached under the item's ID.
        guard let finished = webView.url, articleHostMatches(finished) else { return }
        readerExtractionAttempted = true
        let itemID = item.id
        Task { @MainActor in
            guard let article = await ArticleReaderService.shared.extractArticle(
                from: webView,
                sourceURL: webView.url
            ) else { return }
            ArticleReaderService.shared.saveArticle(article, for: itemID)
            item.readTimeMinutes = article.readMinutes
            try? modelContext.save()
            // Switching into Reader drops a live-page selection with the page.
            if prefersReaderMode {
                selectedText = nil
                selectionGeometry = nil
            }
            withAnimation(.easeOut(duration: 0.2)) { readerArticle = article }
        }
    }

    /// Whether a finished navigation is on the item's own host, tolerating
    /// http/https and www differences (the macOS reader's rule).
    private func articleHostMatches(_ url: URL) -> Bool {
        guard let sourceHost = articleURL?.host?.lowercased(),
              let finishedHost = url.host?.lowercased() else { return false }
        func stripWWW(_ host: String) -> String { host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
        return stripWWW(sourceHost) == stripWWW(finishedHost)
    }

    private func setReaderMode(_ isReader: Bool) {
        guard canToggleReaderMode, prefersReaderMode != isReader else { return }
        // A selection belongs to the pane it was made in, and a pending
        // highlight jump must not replay when the other pane mounts.
        selectedText = nil
        selectionGeometry = nil
        scrollToTextQuery = ""
        ReaderModePreference.setPrefersLive(!isReader, for: item.id)
        withAnimation(.easeOut(duration: 0.2)) { prefersReaderMode = isReader }
    }

    /// Links stay inside the reader: the live page navigates there and comes
    /// forward while the destination is on screen. Reader stays the standing
    /// choice and returns by itself once Back lands on the item's own page.
    private func openLinkFromReader(_ link: URL) {
        selectedText = nil
        selectionGeometry = nil
        scrollToTextQuery = ""
        hasMountedLiveView = true
        pendingNavigationURL = link
        navigationToken += 1
    }

    /// Persists Reader's scroll position (0–1) to item metadata past a 0.05
    /// delta, like the macOS reader, so reopening restores it without every
    /// scroll event dirtying the item.
    private func updateReadingProgress(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        let reachedEnd = clamped >= 0.995 && lastSavedReadingProgress < 0.995
        guard abs(clamped - lastSavedReadingProgress) >= 0.05 || reachedEnd else { return }
        lastSavedReadingProgress = clamped
        item.readingProgress = clamped
        try? modelContext.save()
    }

    private func stepReaderTextSize(_ delta: Int) {
        let range = ReaderTypographySettings.sizeStepRange
        readerSizeStep = min(max(readerSizeStep + delta, range.lowerBound), range.upperBound)
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
            .padding(Spacing.xl)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
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
                    BoardSuggestionMetadata.clearPendingSuggestion(on: target)
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
            BoardSuggestionMetadata.clearPendingSuggestion(on: target)
            itemViewModel.assignToBoard(target, board: existing)
        } else {
            let board = Board(title: title)
            modelContext.insert(board)
            BoardSuggestionMetadata.clearPendingSuggestion(on: target)
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

    /// iPad has room for every action. iPhone shows three besides Back —
    /// Reader | Live, Reflections, and an overflow menu holding the rest —
    /// instead of letting the system push an arbitrary few into its own "…".
    private var showsFullToolbar: Bool {
        horizontalSizeClass == .regular
    }

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
            Group {
                // Reader | Live (articles only). The glyph names what is on
                // screen — the macOS rule: what is lit is what is shown.
                if supportsReaderMode {
                    readerModeToggle
                }

                if showsFullToolbar {
                    flashcardsMenu
                    // Text size in Reader, page zoom on the live page, and
                    // find (web pages only)
                    if showsWebPageControls {
                        textSizeMenu
                        findButton
                    }
                    reflectionsButton
                    discussButton
                    #if os(iOS)
                    shareButton
                    #endif
                    infoButton
                } else {
                    reflectionsButton
                    overflowMenu
                }
            }
            .fontWeight(.medium)
            .tint(Color.textPrimary)
        }
    }

    /// iPhone's overflow, in a fixed order: Info, Discuss, Share, Find,
    /// Text size, then Flashcards. Menus inside it open as submenus.
    private var overflowMenu: some View {
        Menu {
            Button {
                showInfoSheet = true
            } label: {
                Label("Info", systemImage: "info.circle")
            }
            discussButton
            #if os(iOS)
            shareButton
            #endif
            if showsWebPageControls {
                findButton
                textSizeMenu
            }
            flashcardsMenu
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }

    /// iPad's Info button. The popover anchors to it, as inspectors do on
    /// iPad; iPhone reaches Info through the overflow and gets a sheet.
    private var infoButton: some View {
        Button {
            showInfoPopover = true
        } label: {
            Label("Info", systemImage: "info.circle")
                .labelStyle(.iconOnly)
                .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Info")
        .popover(isPresented: $showInfoPopover, arrowEdge: .top) {
            infoPanel
                .frame(width: 380, height: 620)
        }
    }

    private var flashcardsMenu: some View {
        Menu {
            Button("New flashcard", systemImage: "plus.rectangle.on.rectangle") {
                flashcardSession = LearningEditorSession(item: resolveWritingHost(), sourceQuote: trimmedSelection)
            }
            Button("Manage flashcards", systemImage: "rectangle.on.rectangle") { showFlashcards = true }
        } label: {
            Label("Flashcards", systemImage: "rectangle.on.rectangle")
        }
        .accessibilityLabel("Flashcards")
    }

    /// Text size in Reader, page zoom on the live page.
    @ViewBuilder
    private var textSizeMenu: some View {
        if showsReaderContent {
            readerTextSizeMenu
        } else {
            pageZoomMenu
        }
    }

    private var findButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) { showFindBar.toggle() }
            if showFindBar { findBarFocused = true }
        } label: {
            Label("Find in Page", systemImage: "doc.text.magnifyingglass")
        }
        .accessibilityLabel("Find in page")
    }

    private var reflectionsButton: some View {
        Button {
            if horizontalSizeClass == .regular {
                reflectionDetent = .large
            }
            showReflections = true
        } label: {
            Label("Reflections", systemImage: "text.bubble")
        }
        .accessibilityLabel("Reflections")
    }

    private var discussButton: some View {
        Button {
            startDiscussion()
        } label: {
            Label("Discuss", systemImage: "bubble.left.and.bubble.right")
        }
        .accessibilityLabel("Discuss")
    }

    #if os(iOS)
    private var shareButton: some View {
        ShareLink(item: shareURL) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel("Share")
    }
    #endif

    /// One tap flips Reader and Live. Disabled (not hidden) while there is no
    /// Reader view of the page on screen — before extraction succeeds, after
    /// it fails, or on a followed link.
    private var readerModeToggle: some View {
        let isReader = showsReaderContent
        return Button {
            setReaderMode(!isReader)
        } label: {
            Image(systemName: isReader ? "doc.plaintext" : "safari")
                .fontWeight(.medium)
                .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                .contentShape(Rectangle())
        }
        .disabled(!canToggleReaderMode)
        .accessibilityLabel("Reader mode")
        .accessibilityValue(isReader ? "On" : "Off")
        .accessibilityHint(isReader ? "Shows the live page" : "Shows the article in Reader")
        .accessibilityAddTraits(.isToggle)
    }

    /// Reader's type scale and typeface — the same settings the macOS reader
    /// keeps, stepped instead of page-zoomed.
    private var readerTextSizeMenu: some View {
        Menu {
            Button { stepReaderTextSize(1) } label: {
                Label("Larger Text", systemImage: "plus.magnifyingglass")
            }
            .disabled(readerSizeStep >= ReaderTypographySettings.sizeStepRange.upperBound)

            Button { stepReaderTextSize(-1) } label: {
                Label("Smaller Text", systemImage: "minus.magnifyingglass")
            }
            .disabled(readerSizeStep <= ReaderTypographySettings.sizeStepRange.lowerBound)

            Divider()

            Picker("Typeface", selection: $readerUseSerif) {
                Text("Serif").tag(true)
                Text("Sans").tag(false)
            }

            Divider()

            Button { readerSizeStep = ReaderTypographySettings.defaultSizeStep } label: {
                Label("Reset Text Size", systemImage: "arrow.counterclockwise")
            }
            .disabled(readerSizeStep == ReaderTypographySettings.defaultSizeStep)
        } label: {
            Label("Text Size", systemImage: "textformat.size")
        }
        .accessibilityLabel("Text size")
    }

    /// The live page's zoom, under the same glyph as Reader's text size.
    private var pageZoomMenu: some View {
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
            Label("Zoom", systemImage: "textformat.size")
        }
        .accessibilityLabel("Zoom")
    }

    // MARK: - Info

    /// The item's Info: connections and backlinks, boards, summary. A
    /// connected item opens in this stack once Info is out of the way.
    private var infoPanel: some View {
        ItemInspectorPanel(item: item) { linkedItem in
            openLinkedItem(linkedItem)
        }
    }

    @ViewBuilder
    private var infoSheetContent: some View {
        infoPanel
            #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
    }

    private func openLinkedItem(_ linkedItem: Item) {
        showInfoSheet = false
        showInfoPopover = false
        guard linkedItem.id != item.id else { return }
        navigateToLinkedItem = linkedItem
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
            .padding(.vertical, Spacing.sm)
            .background(Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(Color.borderPrimary, lineWidth: 1)
            )

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
                withAnimation(reduceMotion ? nil : .default) {
                    showFindBar = false
                    findQuery = ""
                    findBarFocused = false
                }
            }
            .font(.groveBody)
        }
        .padding(.horizontal, LayoutDimensions.contentPaddingH)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.borderPrimary)
                .frame(height: 1)
        }
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

    // MARK: - Actions

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

// MARK: - Reader mode preference

/// The per-item Reader | Live choice. The macOS reader keeps no per-item
/// choice (it opens into Reader whenever an article exists), so this is a
/// device-local UserDefaults key per item. Reader is the default, so only a
/// departure from it is stored.
private enum ReaderModePreference {
    private static func key(for itemID: UUID) -> String {
        "reader.mode.prefersLive.\(itemID.uuidString)"
    }

    static func prefersLive(_ itemID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: itemID))
    }

    static func setPrefersLive(_ prefersLive: Bool, for itemID: UUID) {
        if prefersLive {
            UserDefaults.standard.set(true, forKey: key(for: itemID))
        } else {
            UserDefaults.standard.removeObject(forKey: key(for: itemID))
        }
    }
}
