import Foundation
import SwiftData
import SwiftUI
import WebKit

@MainActor
@Observable
final class ItemReaderViewModel {
    struct FlashcardSelection: Identifiable {
        let id = UUID()
        let item: Item
        let reflection: ReflectionBlock?
        let quote: String?
    }

    // MARK: - Dependencies

    var item: Item
    var modelContext: ModelContext
    var onNavigateToItem: ((Item) -> Void)?

    // MARK: - Business State

    var isEditingContent = false
    var showArticleWebView = false
    /// Whether the native PDF pane is up. A separate flag from
    /// `showArticleWebView` on purpose: the two panes are mutually exclusive
    /// surfaces, and everything keyed off the web flag (⌘F routing to
    /// find-in-page, Reader mode, capture-on-write) means nothing here.
    var showPDFReader = false
    var isEditingSummary = false
    var editableSummary = ""
    var isReflectionPanelCollapsed = false
    var editingBlock: ReflectionBlock?
    var showReflectionEditor = false
    var blockToDelete: ReflectionBlock?
    var flashcardSelection: FlashcardSelection?
    private var reflectionPanelWasCollapsedBeforeFlashcard = false

    // MARK: - Video State

    var videoCurrentTime: Double = 0
    var videoDuration: Double = 0
    var videoSeekTarget: Double? = nil

    // MARK: - Zoom State

    var webViewZoomLevel: CGFloat = 1.0

    // MARK: - Find State

    var showFindBar = false
    var findQuery = ""
    var findMatchCount = 0
    var findCurrentMatch = 0
    var findForwardToken = 0
    var findBackwardToken = 0

    // MARK: - Reader Mode State

    /// Extracted readable article (from disk cache or live extraction).
    var readerArticle: ReadableArticle? = nil
    /// Whether the web panel currently shows Reader mode vs. the original page.
    var isReaderMode = false
    /// Extraction is attempted at most once per item visit.
    var readerExtractionAttempted = false
    /// Latest text selection reported from either web mode (future highlight plumbing).
    var webSelectedText: String? = nil
    /// Where that selection sits, in the web view's viewport coordinates.
    /// nil when the selection has no usable geometry (collapsed range, or a
    /// surface that reports text only) — the action bar then falls back to
    /// its pane-bottom placement.
    var webSelectionGeometry: WebSelectionGeometry? = nil
    /// Scroll-to-text request routed to whichever web mode is active.
    var scrollToTextQuery = ""
    var scrollToTextToken = 0
    /// Current URL of the web panel while browsing (nil when on the item's
    /// own page or not in web mode). Drives capture-on-write for pages
    /// navigated to inside the reader.
    var navigatedWebURL: URL? = nil
    /// Reader extraction for a page navigated to inside the pane. Held in
    /// memory only — never written to the item's disk cache, which belongs to
    /// the item's own article. Cleared whenever navigation moves elsewhere.
    var navigatedReaderArticle: ReadableArticle? = nil
    /// URL `navigatedReaderArticle` was extracted from, so a stale extraction
    /// is never shown for a page the user has since navigated away from.
    var navigatedReaderArticleURL: URL? = nil
    /// URL whose extraction has already been attempted, successfully or not.
    /// Marks the point where a page's readability stops being an open question.
    var navigatedExtractionAttemptedURL: URL? = nil
    /// Pending in-pane navigation request (a link tapped in Reader mode).
    var pendingNavigationURL: URL? = nil
    var pendingNavigationToken = 0
    /// Transient "saved to library" feedback for silent captures.
    var showAutoCaptureIndicator = false

    private var lastSavedReadingProgress: Double = -1
    /// Latest scroll fraction (not persisted every event; see updateReadingProgress).
    private(set) var liveReadingProgress: Double = 0

    /// The current text selection eligible for highlighting (trimmed, non-empty),
    /// or nil. Single source of truth for the web panel and native-content bars.
    var highlightableSelection: String? {
        guard let text = webSelectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Init

    init(item: Item, modelContext: ModelContext, onNavigateToItem: ((Item) -> Void)? = nil) {
        self.item = item
        self.modelContext = modelContext
        self.onNavigateToItem = onNavigateToItem
    }

    // MARK: - Computed Properties

    var sortedReflections: [ReflectionBlock] {
        item.reflections.sorted { $0.position < $1.position }
    }

    var isVideoItem: Bool {
        item.type == .video && localVideoURL != nil
    }

    /// True when this item's source is a PDF document. Such an item reads in
    /// the native PDF pane, never the web pane: WKWebView's PDF plugin renders
    /// the file but leaves selection, find, Reader mode and reading progress
    /// silently inert.
    var isPDFItem: Bool {
        item.isPDFDocument
    }

    /// The document a PDF item stands for.
    var pdfSourceURL: URL? {
        guard isPDFItem else { return nil }
        return resolvedSourceURL(from: item.sourceURL)
    }

    /// URL that can be loaded in the in-app WebView (article/codebase items,
    /// not local video, not PDFs).
    var articleURL: URL? {
        guard (item.type == .article || item.type == .codebase),
              !isPDFItem,
              item.metadata["videoLocalFile"] != "true" else { return nil }

        return resolvedSourceURL(from: item.sourceURL)
    }

    /// The player for a video that was never downloaded: a privacy-enhanced
    /// embed for hosts we know, the watch page itself for the rest. Nil for
    /// every item that has a local file to play or no web source at all.
    var remoteVideoEmbedURL: URL? {
        guard item.type == .video, localVideoURL == nil else { return nil }
        return VideoEmbed.remoteURL(sourceURL: item.sourceURL, metadata: item.metadata)
    }

    /// True for every video item — whether the pane is showing an embed or a
    /// local file, there is no prose here for Readability to extract — and for
    /// every PDF, which never reaches a web view at all. The reader must not
    /// try either way, and the READER | ORIGINAL control stays off screen.
    var suppressesReaderMode: Bool {
        item.type == .video || isPDFItem
    }

    /// What the reader's web panel loads. An article or codebase page loads
    /// itself; a remote video loads its embed, so a YouTube or Vimeo item opens
    /// into a player instead of dead-ending on its own OG description. Nil for
    /// a PDF: `articleURL` excludes them, so the web branch never selects one.
    var readerWebURL: URL? {
        articleURL ?? remoteVideoEmbedURL
    }

    /// Whether `url` is a page other than the one this item stands for.
    ///
    /// The same question as `ReadingCapture.isDifferentPage`, except that a
    /// remote video's embed *is* the item's own page: the panel deliberately
    /// loads the player rather than the watch page, and nothing downstream —
    /// capture-on-write, provenance, the history chevrons — should read that
    /// substitution as the reader having followed a link.
    func isDifferentPageFromItem(_ url: URL) -> Bool {
        if isSameWebPage(url, remoteVideoEmbedURL) { return false }
        return ReadingCapture.isDifferentPage(url, from: item)
    }

    /// Resolve the local video file URL for this item
    var localVideoURL: URL? {
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

    // MARK: - Zoom

    func zoomIn() {
        webViewZoomLevel = min(webViewZoomLevel + 0.1, 2.0)
    }

    func zoomOut() {
        webViewZoomLevel = max(webViewZoomLevel - 0.1, 0.5)
    }

    func resetZoom() {
        webViewZoomLevel = 1.0
    }

    var zoomPercentage: Int {
        Int(round(webViewZoomLevel * 100))
    }

    // MARK: - Reader Mode

    /// Persisted 0–1 reading progress for this item.
    var readingProgress: Double {
        Double(item.metadata["readingProgress"] ?? "") ?? 0
    }

    /// Loads a cached extraction if present, and opens straight into Reader
    /// mode (offline-capable) when one exists.
    func loadCachedReaderArticleIfAvailable() {
        guard readerArticle == nil, !suppressesReaderMode else { return }
        guard let cached = ArticleReaderService.shared.cachedArticle(for: item.id) else { return }
        readerArticle = cached
        isReaderMode = true
        if item.metadata["readTimeMinutes"] == nil {
            item.metadata["readTimeMinutes"] = String(cached.readMinutes)
        }
    }

    /// Called when the live page finishes loading: runs Readability extraction
    /// once. On success caches the result and auto-switches to Reader mode;
    /// on failure (null parse, error, paywall shell) stays on the live page
    /// silently.
    func handleArticlePageDidFinish(_ webView: WKWebView) {
        // A video has no article to extract. Readability on a player page
        // yields an empty shell at best, so the reader never offers a Reader
        // mode for one — the absence of any extraction is what keeps the
        // READER | ORIGINAL control off screen.
        guard !suppressesReaderMode else { return }

        // A page the user navigated to inside the pane gets its own extraction
        // so Reader mode reflects what is on screen. It is deliberately kept
        // out of the item's disk cache — only the item's own article belongs
        // there — but without this, toggling Reader on a link target fell back
        // to the root article and showed the wrong page entirely.
        if let finished = webView.url, hasNavigatedAwayFromOwnPage(finished) {
            extractNavigatedArticle(from: webView, url: finished)
            return
        }

        guard readerArticle == nil, !readerExtractionAttempted else { return }
        // Only extract when the finished page is actually this item's article —
        // not a consent interstitial, redirect shell on another host, or a link
        // the user clicked. Otherwise the wrong page gets cached under this
        // item's ID and shown as its reader content forever.
        guard let finished = webView.url, articleURLMatches(finished) else { return }
        readerExtractionAttempted = true
        let itemID = item.id
        Task { @MainActor in
            guard let article = await ArticleReaderService.shared.extractArticle(
                from: webView,
                sourceURL: webView.url
            ) else { return }
            ArticleReaderService.shared.saveArticle(article, for: itemID)
            readerArticle = article
            item.metadata["readTimeMinutes"] = String(article.readMinutes)
            try? modelContext.save()
            withAnimation(.easeOut(duration: 0.2)) { isReaderMode = true }
        }
    }

    /// The article Reader mode should render right now: the navigated page's
    /// extraction when the pane has browsed away from the item's own article,
    /// otherwise the item's cached article.
    var activeReaderArticle: ReadableArticle? {
        if let navigated = navigatedWebURL {
            guard let extracted = navigatedReaderArticle,
                  navigatedReaderArticleURL?.absoluteString == navigated.absoluteString
            else { return nil }
            return extracted
        }
        return readerArticle
    }

    /// True while the pane sits on a followed link whose readability is still
    /// an open question — the page is loading, or its extraction is in flight.
    /// The Reader control stays mounted across this window instead of blinking
    /// out between pages, and retires only if the destination proves unreadable.
    var isResolvingNavigatedArticle: Bool {
        guard !suppressesReaderMode else { return false }
        guard let navigated = navigatedWebURL else { return false }
        if navigatedReaderArticleURL?.absoluteString == navigated.absoluteString { return false }
        return navigatedExtractionAttemptedURL?.absoluteString != navigated.absoluteString
    }

    /// Extracts a readable article for a page navigated to inside the pane.
    /// Memory-only: nothing here is written to the item's cache.
    private func extractNavigatedArticle(from webView: WKWebView, url: URL) {
        // Already have this exact page extracted.
        guard navigatedReaderArticleURL?.absoluteString != url.absoluteString else { return }
        navigatedReaderArticle = nil
        navigatedReaderArticleURL = nil
        Task { @MainActor in
            let article = await ArticleReaderService.shared.extractArticle(
                from: webView,
                sourceURL: url
            )
            // The pane may have navigated on while extraction was in flight.
            guard webView.url?.absoluteString == url.absoluteString else { return }
            navigatedExtractionAttemptedURL = url
            // A page that won't parse — a login wall, an app shell, a feed —
            // simply stays on the live page. No error, no empty reader.
            guard let article else { return }
            // Reader mode is a preference, not a per-page choice: with
            // `isReaderMode` still set, publishing the extraction is what
            // carries the reader across the link — no second toggle click.
            withAnimation(.easeOut(duration: 0.2)) {
                navigatedReaderArticle = article
                navigatedReaderArticleURL = url
            }
        }
    }

    /// True when `url` is a page reached inside the pane rather than the item's
    /// own source. Compared on the app's normalized URL form so a canonical
    /// redirect (trailing slash, utm strip) isn't mistaken for a link click —
    /// with a host-level fallback for the very first load, where a consent or
    /// redirect shell still counts as the item's own page.
    private func hasNavigatedAwayFromOwnPage(_ url: URL) -> Bool {
        if !isDifferentPageFromItem(url) { return false }
        if readerArticle == nil, !readerExtractionAttempted, articleURLMatches(url) { return false }
        return true
    }

    /// Whether a finished web navigation is the item's own article, tolerating
    /// http/https and www differences but rejecting other hosts.
    private func articleURLMatches(_ url: URL) -> Bool {
        guard let source = item.sourceURL,
              let sourceHost = URL(string: source)?.host?.lowercased(),
              let finishedHost = url.host?.lowercased() else { return false }
        func stripWWW(_ h: String) -> String { h.hasPrefix("www.") ? String(h.dropFirst(4)) : h }
        return stripWWW(sourceHost) == stripWWW(finishedHost)
    }

    /// Persists throttled reading progress (0–1) to item metadata. Only touches
    /// the model past a 0.05 delta so continuous scrolling (~4 reports/sec)
    /// doesn't dirty the Item and fan out observation invalidations on every
    /// scroll event.
    func updateReadingProgress(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        liveReadingProgress = clamped
        guard abs(clamped - lastSavedReadingProgress) >= 0.05 || clamped >= 0.995 else { return }
        lastSavedReadingProgress = clamped
        item.metadata["readingProgress"] = String(format: "%.3f", clamped)
        try? modelContext.save()
    }

    /// Scrolls the active web mode (Reader or Original) to the first
    /// occurrence of the given text.
    func scrollToText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        scrollToTextQuery = trimmed
        scrollToTextToken += 1
    }

    /// Jumps to a saved highlight in the source article, opening the web
    /// panel first if it is not currently visible.
    func jumpToHighlight(_ text: String) {
        guard articleURL != nil else { return }
        // Set the scroll request unconditionally; the web view applies it once
        // its page finishes loading (see the pending-scroll handling in
        // ArticleWebView / ReaderModeWebView), so this works whether the panel
        // was already open or is only now mounting — no fixed-delay guess.
        if !showArticleWebView {
            withAnimation(.easeOut(duration: 0.2)) { showArticleWebView = true }
        }
        scrollToText(text)
    }

    // MARK: - Reflection Host

    /// The item a new reflection/highlight should attach to. Normally the
    /// reader's own item — but when the user has browsed to a different
    /// page inside the web panel, writing silently captures that page into
    /// the library (unfiled, skipping inbox triage) and attaches there.
    private func reflectionHost() -> Item {
        guard showArticleWebView else { return item }
        let resolution = ReadingCapture.host(
            for: item,
            navigatedURL: navigatedWebURL,
            in: modelContext
        )
        if resolution.didCapture {
            flashAutoCaptureIndicator()
        }
        return resolution.host
    }

    private func flashAutoCaptureIndicator() {
        showAutoCaptureIndicator = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            showAutoCaptureIndicator = false
        }
    }

    private func promoteAfterWriting(_ host: Item) {
        ReadingCapture.promoteAfterWriting(host, in: modelContext)
    }

    // MARK: - Highlights

    /// Creates a standalone highlight block (source quote with no prose yet)
    /// from the current text selection.
    func addHighlight(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let host = reflectionHost()
        let nextPosition = (host.reflections.map(\.position).max() ?? -1) + 1
        let timestamp: Int? = isVideoItem ? Int(videoCurrentTime) : nil
        let block = ReflectionBlock(
            item: host,
            blockType: .keyInsight,
            content: "",
            highlight: trimmed,
            position: nextPosition,
            videoTimestamp: timestamp
        )
        modelContext.insert(block)
        host.reflections.append(block)
        promoteAfterWriting(host)
        host.updatedAt = .now
        try? modelContext.save()
        // Dismisses the bar. In Reader mode the new block's highlight string
        // is picked up by the mark injection on the next render pass, which is
        // what makes the click visible on the page.
        webSelectedText = nil
        webSelectionGeometry = nil
    }

    // MARK: - Find Bar

    func closeFindBar() {
        showFindBar = false
        findQuery = ""
        findMatchCount = 0
        findCurrentMatch = 0
    }

    // MARK: - Reflection Editor

    func openFlashcardEditor(quote: String? = nil, reflection: ReflectionBlock? = nil) {
        if flashcardSelection == nil {
            reflectionPanelWasCollapsedBeforeFlashcard = isReflectionPanelCollapsed
        }
        if showReflectionEditor { closeReflectionEditor() }
        let host = reflection?.item ?? reflectionHost()
        let selectedQuote = quote ?? reflection?.highlight
        flashcardSelection = FlashcardSelection(item: host, reflection: reflection, quote: selectedQuote)
        isReflectionPanelCollapsed = false
        webSelectedText = nil
        webSelectionGeometry = nil
        NotificationCenter.default.post(name: .groveEnterFocusMode, object: nil)
    }

    func closeFlashcardEditor() {
        guard flashcardSelection != nil else { return }
        flashcardSelection = nil
        isReflectionPanelCollapsed = reflectionPanelWasCollapsedBeforeFlashcard
        // A reader with reflections already owns focus. Leave its saved
        // window chrome intact until that reader is closed.
        if sortedReflections.isEmpty {
            NotificationCenter.default.post(name: .groveExitFocusMode, object: nil)
        }
    }

    func openBlockForEditing(_ block: ReflectionBlock, focusTrigger: @escaping () -> Void) {
        flashcardSelection = nil
        if isReflectionPanelCollapsed { isReflectionPanelCollapsed = false }
        editingBlock = block
        withAnimation(.easeOut(duration: 0.25)) {
            showReflectionEditor = true
        }
        NotificationCenter.default.post(name: .groveEnterFocusMode, object: nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focusTrigger()
        }
    }

    func openReflectionEditor(type: ReflectionBlockType, content: String, highlight: String?, focusTrigger: @escaping () -> Void) {
        flashcardSelection = nil
        if isReflectionPanelCollapsed { isReflectionPanelCollapsed = false }
        let host = reflectionHost()
        let nextPosition = (host.reflections.map(\.position).max() ?? -1) + 1
        let timestamp: Int? = isVideoItem ? Int(videoCurrentTime) : nil
        let block = ReflectionBlock(
            item: host,
            blockType: type,
            content: content,
            highlight: highlight,
            position: nextPosition,
            videoTimestamp: timestamp
        )
        modelContext.insert(block)
        host.reflections.append(block)
        editingBlock = block
        withAnimation(.easeOut(duration: 0.25)) {
            showReflectionEditor = true
        }
        NotificationCenter.default.post(name: .groveEnterFocusMode, object: nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focusTrigger()
        }
    }

    func toggleReflectionEditor(focusTrigger: @escaping () -> Void) {
        if showReflectionEditor {
            closeReflectionEditor()
        } else {
            openReflectionEditor(type: .keyInsight, content: "", highlight: nil, focusTrigger: focusTrigger)
        }
    }

    func closeReflectionEditor() {
        if let block = editingBlock {
            // The block may live on a captured page item rather than the
            // reader's own item (capture-on-write); operate on its owner.
            let host = block.item ?? item
            let trimmed = block.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasHighlight = !(block.highlight ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if trimmed.isEmpty && !hasHighlight {
                // Empty block with no highlight -- clean up orphan.
                // A pure highlight (empty content, non-empty highlight) is valid.
                host.reflections.removeAll { $0.id == block.id }
                modelContext.delete(block)
                host.updatedAt = .now
            } else {
                promoteAfterWriting(host)
                host.updatedAt = .now
                if !trimmed.isEmpty {
                    WikiLinkSync.sync(item: host, content: block.content, modelContext: modelContext)
                }
            }
            try? modelContext.save()
        }
        withAnimation(.easeOut(duration: 0.25)) {
            showReflectionEditor = false
        }
        editingBlock = nil
        NotificationCenter.default.post(name: .groveExitFocusMode, object: nil)
    }

    // MARK: - Block CRUD

    func deleteBlock(_ block: ReflectionBlock) {
        withAnimation(.easeOut(duration: 0.25)) {
            item.reflections.removeAll { $0.id == block.id }
            modelContext.delete(block)
            item.updatedAt = .now
            try? modelContext.save()
        }
    }

    func requestDeleteBlock(_ block: ReflectionBlock) -> Bool {
        blockToDelete = block
        return true
    }

    func confirmDeleteBlock() {
        if let block = blockToDelete {
            deleteBlock(block)
        }
        blockToDelete = nil
    }

    func cancelDeleteBlock() {
        blockToDelete = nil
    }

    // MARK: - Summary Editing

    func beginEditingSummary(currentSummary: String) {
        editableSummary = currentSummary
        isEditingSummary = true
    }

    func finishEditingSummary() {
        let trimmed = editableSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            item.metadata["summary"] = String(trimmed.prefix(120))
        }
        isEditingSummary = false
        try? modelContext.save()
    }

    // MARK: - Review Banner

    func acceptReview() {
        item.metadata["summaryReviewPending"] = nil
        item.metadata["overviewReviewPending"] = nil
        try? modelContext.save()
    }

    func revertOverview() {
        if let original = item.metadata["originalDescription"], !original.isEmpty {
            item.content = original
            item.metadata["hasLLMOverview"] = nil
            item.metadata["overviewReviewPending"] = nil
            item.metadata["originalDescription"] = nil
            try? modelContext.save()
        }
    }

    func dismissReview() {
        item.metadata["summaryReviewPending"] = nil
        item.metadata["overviewReviewPending"] = nil
        try? modelContext.save()
    }

    // MARK: - Content Editing

    func toggleContentEditing() {
        let wasEditing = isEditingContent
        isEditingContent.toggle()
        if wasEditing {
            if item.metadata["isAIGenerated"] == "true" && item.metadata["isAIEdited"] != "true" {
                item.metadata["isAIEdited"] = "true"
            }
            WikiLinkSync.sync(item: item, modelContext: modelContext)
        }
    }

    // MARK: - Wiki-Link Navigation

    func navigateToItemByTitle(_ title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let allItems: [Item] = modelContext.fetchAll()
        if let matchedItem = ItemResolver.resolveExactTitle(trimmedTitle, in: allItems) {
            onNavigateToItem?(matchedItem)
        }
    }

    // MARK: - Thumbnail Backfill

    /// Downloads cover image for existing items that have a thumbnailURL but no stored thumbnail.
    func backfillThumbnailIfNeeded() {
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

    // MARK: - Item Change Reset

    func resetOnItemChange() {
        flashcardSelection = nil
        isEditingContent = false
        if showReflectionEditor { closeReflectionEditor() }
        showArticleWebView = false
        showPDFReader = false
        isEditingSummary = false
        editableSummary = ""
        isReflectionPanelCollapsed = false
        webViewZoomLevel = 1.0
        closeFindBar()
        readerArticle = nil
        navigatedReaderArticle = nil
        navigatedReaderArticleURL = nil
        navigatedExtractionAttemptedURL = nil
        navigatedWebURL = nil
        pendingNavigationURL = nil
        isReaderMode = false
        readerExtractionAttempted = false
        webSelectedText = nil
        webSelectionGeometry = nil
        scrollToTextQuery = ""
        lastSavedReadingProgress = -1
    }
}
