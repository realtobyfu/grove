import SwiftUI
import SwiftData
import WebKit
#if os(macOS)
import AppKit
#endif

struct ItemReaderWebViewPanel: View {
    @Bindable var vm: ItemReaderViewModel
    let url: URL
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    var focusTrigger: () -> Void
    /// Unified selection callback: fires with the selected text in EITHER
    /// mode (Reader or Original), nil when the selection is cleared.
    var onTextSelected: ((String?) -> Void)? = nil

    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var currentWebURL: URL? = nil
    @State private var goBackToken = 0
    @State private var goForwardToken = 0
    /// Library item backing the page currently on screen, if it has one.
    /// Drives the capture FAB's state; nil means the page is unsaved.
    @State private var capturedItem: Item? = nil
    @State private var showCapturePicker = false
    /// Keeps the FAB on screen briefly after filing so the checkmark can
    /// confirm the action before the button retires from the page.
    @State private var showFiledConfirmation = false
    /// Held so a rapid second filing cancels the first timer instead of
    /// having it truncate the new confirmation.
    @State private var filedConfirmationTask: Task<Void, Never>? = nil
    /// True once the live page has been shown for this item. It then stays
    /// mounted (hidden) behind Reader mode so web history survives toggling.
    /// Starts false so an item that opens straight into a cached Reader
    /// article never fetches the live page.
    @State private var hasMountedWebView = false
    /// Live width of the navigation strip, which drives how much of it can
    /// stay on the strip rather than folding into the `…` menu.
    @State private var stripWidth: CGFloat = 0
    #if os(macOS)
    /// Mirrors the window's full-screen state so the reader's own menu item can
    /// name what the next activation will do.
    @State private var isFullScreen = false
    /// The window this panel actually lives in. Window-level notifications are
    /// broadcast for every window, so without this the panel would follow a
    /// different window's full-screen transitions.
    @State private var hostWindow: NSWindow? = nil
    #endif

    // Reader typography (persisted app-wide)
    @AppStorage(ReaderTypographySettings.sizeStepKey) private var readerSizeStep = 1
    @AppStorage(ReaderTypographySettings.isWideKey) private var readerIsWide = false
    @AppStorage(ReaderTypographySettings.useSerifKey) private var readerUseSerif = true

    private var readerTypography: ReaderTypographySettings {
        ReaderTypographySettings(sizeStep: readerSizeStep, isWide: readerIsWide, useSerif: readerUseSerif)
    }

    private var showsReaderContent: Bool {
        vm.isReaderMode && vm.activeReaderArticle != nil
    }

    /// The Reader|Original control belongs on screen whenever this page has a
    /// reader view — or might still turn out to have one. It retires only for
    /// pages that have proved unreadable, which is the silent failure the
    /// reader promises rather than an error message.
    private var showsReaderModeControl: Bool {
        vm.activeReaderArticle != nil || vm.isResolvingNavigatedArticle
    }

    /// Back can walk web history, or fall through to the article's own
    /// page when the pane mounted directly on a link target. Works in Reader
    /// mode too: the live page stays mounted underneath, so its history is
    /// still the pane's history and Reader content follows wherever it lands.
    private var webBackEnabled: Bool {
        if canGoBack { return true }
        if let current = currentWebURL, current.absoluteString != url.absoluteString { return true }
        // The VM can know the pane left the item's page even when the web
        // view's own reporting doesn't — a pane mounted directly on a link
        // target (image documents especially) records no history entry.
        if vm.navigatedWebURL != nil { return true }
        return false
    }

    private var webForwardEnabled: Bool {
        canGoForward
    }

    /// The page-history chevrons earn their place only once this session has
    /// somewhere to go. Back at the item's own page with no history they
    /// leave again, so "Overview" is the only back-shaped control on screen.
    private var showsWebHistory: Bool {
        webBackEnabled || webForwardEnabled
    }

    /// Width of the collapsing history slot: divider + two chevron targets +
    /// the 10pt gaps around them. Fixed so the slot can animate between 0 and
    /// its full size without the domain text reflowing. iOS uses 44pt touch
    /// targets, so its slot is wider.
    #if os(iOS)
    private static let historySlotWidth: CGFloat = 119
    #else
    private static let historySlotWidth: CGFloat = 55
    #endif

    /// How much of the strip the reading pane can actually seat. The width
    /// ladder and what each rung seats live in `ReaderStripLayout`.
    private var stripTier: ReaderStripLayout.Tier {
        ReaderStripLayout.tier(forWidth: stripWidth)
    }

    /// Whether `control` keeps its own slot on the strip at the current width.
    private func onStrip(_ control: ReaderStripLayout.Control) -> Bool {
        ReaderStripLayout.isOnStrip(control, in: stripTier)
    }

    /// Whether `control` has folded into the `…` menu at the current width.
    private func inMenu(_ control: ReaderStripLayout.Control) -> Bool {
        ReaderStripLayout.isFoldedIntoMenu(control, in: stripTier)
    }

    /// Non-empty trimmed selection from either web mode, or nil.
    var body: some View {
        VStack(spacing: 0) {
            // Slim navigation bar
            HStack(spacing: 10) {
                // Where-am-I cluster: the single root affordance, the page
                // history when there is any, then the current host.
                HStack(spacing: 0) {
                    overviewButton
                        .padding(.trailing, 10)

                    // The history chevrons exist only once this reading
                    // session has actually navigated somewhere. The slot
                    // animates its width, so the domain glides rather than
                    // jumping when they arrive or leave.
                    webHistoryControls
                        .frame(width: showsWebHistory ? Self.historySlotWidth : 0, alignment: .leading)
                        .opacity(showsWebHistory ? 1 : 0)
                        .clipped()
                        .allowsHitTesting(showsWebHistory)
                        .accessibilityHidden(!showsWebHistory)

                    domainLabel
                }
                .animation(.easeOut(duration: 0.18), value: showsWebHistory)
                // The domain is the one thing here that can afford to lose
                // width, so it yields before any control is squeezed.
                .layoutPriority(-1)

                Spacer(minLength: 8)

                // Text size in Reader, page zoom on the live page. One tap
                // each — burying these a level down in the menu costs a click
                // on the thing most likely to be adjusted mid-article, so they
                // outrank every other trailing control and only fold away when
                // the strip has nothing left to give.
                if onStrip(.sizeControls) {
                    if showsReaderContent {
                        typographyControls
                    } else {
                        zoomControls
                    }

                    Divider().frame(height: 12)
                }

                #if os(macOS)
                // Full screen is a standing choice about the window, not a
                // reading setting, so it keeps its own target rather than
                // hiding a level down in the menu — until the strip can no
                // longer seat it.
                if onStrip(.fullScreen) {
                    fullScreenButton
                }
                #endif

                readerSettingsMenu

                if onStrip(.readerMode), showsReaderModeControl {
                    Divider().frame(height: 12)

                    readerModeControl
                }

                if onStrip(.reflect) {
                    Divider().frame(height: 12)

                    reflectButton
                }

                if vm.showAutoCaptureIndicator {
                    // Inline confirmation for capture-on-write.
                    Label("Saved", systemImage: "checkmark.circle")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }

                if onStrip(.openInBrowser) {
                    openInBrowserButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.bgCard)
            .background {
                // What the strip can seat depends on how wide the reading pane
                // is, which changes with the sidebar, the inspector and the
                // window all at once — so it is measured rather than guessed.
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { stripWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in stripWidth = width }
                }
            }
            .animation(.easeOut(duration: 0.18), value: stripTier)
            Divider()

            if vm.showFindBar && !showsReaderContent {
                ItemReaderFindBar(vm: vm)
            }

            ZStack(alignment: .bottom) {
                // The live page stays mounted underneath Reader mode once it
                // has been shown. Tearing it down on every toggle threw away
                // the web history and the page being viewed, which is what
                // made Back erratic and sent the Reader toggle back to the
                // item's root article instead of the page on screen.
                if !showsReaderContent || hasMountedWebView {
                    originalContent
                        .opacity(showsReaderContent ? 0 : 1)
                        .allowsHitTesting(!showsReaderContent)
                        .accessibilityHidden(showsReaderContent)
                }

                if showsReaderContent, let article = vm.activeReaderArticle {
                    readerContent(article: article)
                }

                if let selection = vm.highlightableSelection {
                    // The web view fills this ZStack, so the reported viewport
                    // coordinates land in the overlay's own coordinate space.
                    HighlightActionBarOverlay(
                        vm: vm,
                        selection: selection,
                        selectionGeometry: vm.webSelectionGeometry,
                        onWrite: { resolveCaptureState() }
                    )
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // One capture affordance for both modes, sitting over the
                // content instead of hiding among the toolbar glyphs.
                // A filed page carries no button — absence means "taken
                // care of" — except for a beat right after filing.
                if captureState != .filed || showFiledConfirmation {
                    captureFAB
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
                }
            }
            .animation(.easeOut(duration: 0.25), value: captureState == .filed && !showFiledConfirmation)
            .animation(.easeOut(duration: 0.15), value: vm.highlightableSelection != nil)
        }
        .onChange(of: showsReaderContent) { _, isReader in
            if !isReader { hasMountedWebView = true }
        }
        .onChange(of: capturePageURL) { _, _ in
            resolveCaptureState()
        }
        // capturedItem is a cached model reference for whatever page is on
        // screen; the deletion notification is the only signal that reference
        // is about to go invalid (the page needn't be the selected item).
        .onReceive(NotificationCenter.default.publisher(for: .groveItemWillDelete)) { note in
            guard let id = NotificationCenter.itemWillDeleteID(from: note) else { return }
            if capturedItem?.id == id {
                capturedItem = nil
                showFiledConfirmation = false
                showCapturePicker = false
            }
        }
        .task(id: url) {
            // Drop any stale scroll-to-text query from a previous panel
            // session so a freshly mounted web view doesn't auto-scroll.
            vm.scrollToTextQuery = ""
            vm.navigatedWebURL = nil
            hasMountedWebView = false
            vm.loadCachedReaderArticleIfAvailable()
            resolveCaptureState()
        }
        // ⌘+ / ⌘− / ⌘⇧0 live in the View menu, so the shortcuts are discoverable
        // and work the same whether the reader is showing parsed text or the
        // live page. The panel is the only thing that knows which that is.
        .onReceive(NotificationCenter.default.publisher(for: .groveReaderTextLarger)) { _ in
            stepTextSize(1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveReaderTextSmaller)) { _ in
            stepTextSize(-1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .groveReaderTextReset)) { _ in
            resetTextSize()
        }
        #if os(macOS)
        .background {
            // ⌘= as an alias for ⌘+, the way browsers accept both. The menu can
            // only advertise one, so the second lives here.
            Button("") { stepTextSize(1) }
                .keyboardShortcut("=", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .background {
            HostWindowReader { window in
                guard window !== hostWindow else { return }
                hostWindow = window
                isFullScreen = Self.windowIsFullScreen(window)
            }
            .frame(width: 0, height: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            guard isHostWindow(note.object) else { return }
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            guard isHostWindow(note.object) else { return }
            isFullScreen = false
        }
        #endif
    }

    // MARK: - Content

    @ViewBuilder
    private func readerContent(article: ReadableArticle) -> some View {
        ReaderModeWebView(
            article: article,
            typography: readerTypography,
            isDark: colorScheme == .dark,
            initialProgress: vm.readingProgress,
            scrollToTextQuery: vm.scrollToTextQuery,
            scrollToTextToken: vm.scrollToTextToken,
            highlights: pageHighlights,
            onTextSelected: { text in
                vm.webSelectedText = text
                onTextSelected?(text)
            },
            onSelectionGeometry: { geometry in
                vm.webSelectionGeometry = geometry
            },
            onScrollProgress: { fraction in
                vm.updateReadingProgress(fraction)
            },
            onOpenExternalLink: { linkURL in
                // Links stay inside the reader: navigate the live page
                // underneath. "Open in Browser" remains the escape hatch.
                //
                // `isReaderMode` is deliberately left alone — it is the user's
                // standing preference, not a per-page state. The pane holds the
                // current article until the destination commits (as a browser
                // does), shows the live page while it is parsed, and returns to
                // Reader by itself if the parse succeeds.
                hasMountedWebView = true
                vm.pendingNavigationURL = linkURL
                vm.pendingNavigationToken += 1
            }
        )
        #if os(iOS)
        .ignoresSafeArea(edges: .bottom)
        #endif
    }

    @ViewBuilder
    private var originalContent: some View {
        #if os(macOS)
        ArticleWebView(
            url: url,
            onTextSelected: { text in
                vm.webSelectedText = text
                onTextSelected?(text)
            },
            onSelectionGeometry: { geometry in
                vm.webSelectionGeometry = geometry
            },
            findQuery: vm.findQuery,
            findForwardToken: vm.findForwardToken,
            findBackwardToken: vm.findBackwardToken,
            onFindResult: { current, total in
                vm.findCurrentMatch = current
                vm.findMatchCount = total
            },
            zoomLevel: vm.webViewZoomLevel,
            goBackToken: goBackToken,
            goForwardToken: goForwardToken,
            navigateURL: vm.pendingNavigationURL,
            navigateToken: vm.pendingNavigationToken,
            onNavigationChanged: { canBack, canFwd, currentURL in
                // A selection belongs to the page it was made on. When the
                // live page moves on while it is what's on screen, retire the
                // selection with it (Reader-mode selections live in the other
                // web view and are left alone).
                if !showsReaderContent, currentURL?.absoluteString != currentWebURL?.absoluteString {
                    vm.webSelectedText = nil
                    vm.webSelectionGeometry = nil
                }
                canGoBack = canBack
                canGoForward = canFwd
                currentWebURL = currentURL
                // Mirror into the VM so capture-on-write knows what page
                // a reflection belongs to. Normalized comparison so a
                // canonical redirect on the item's own URL doesn't read as
                // a link the user followed.
                let onArticlePage = currentURL.map { !vm.isDifferentPageFromItem($0) } ?? true
                // No withAnimation here: this callback can fire synchronously
                // from updateNSView, and an implicit transaction would animate
                // every animatable in the pass. The nav bar owns its own
                // .animation(_:value:) scoping.
                vm.navigatedWebURL = onArticlePage ? nil : currentURL
                // Back at the item's own page the detour is over: the pending
                // link is spent, and Reader mode — never having been switched
                // off — comes back with the item's own article.
                if onArticlePage {
                    vm.pendingNavigationURL = nil
                }
            },
            onPageFinished: { webView in
                vm.handleArticlePageDidFinish(webView)
            },
            scrollToTextQuery: vm.scrollToTextQuery,
            scrollToTextToken: vm.scrollToTextToken
        )
        #else
        MobileArticleWebView(
            url: url,
            onTextSelected: { text in
                vm.webSelectedText = text
                onTextSelected?(text)
            },
            onSelectionGeometry: { geometry in
                vm.webSelectionGeometry = geometry
            },
            findQuery: vm.findQuery,
            findForwardToken: vm.findForwardToken,
            findBackwardToken: vm.findBackwardToken,
            onFindResult: { current, total in
                vm.findCurrentMatch = current
                vm.findMatchCount = total
            },
            zoomLevel: vm.webViewZoomLevel,
            scrollToTextQuery: vm.scrollToTextQuery,
            scrollToTextToken: vm.scrollToTextToken,
            goBackToken: goBackToken,
            goForwardToken: goForwardToken,
            navigateURL: vm.pendingNavigationURL,
            navigateToken: vm.pendingNavigationToken,
            onNavigationChanged: { canBack, canFwd, currentURL in
                if !showsReaderContent, currentURL?.absoluteString != currentWebURL?.absoluteString {
                    vm.webSelectedText = nil
                    vm.webSelectionGeometry = nil
                }
                canGoBack = canBack
                canGoForward = canFwd
                currentWebURL = currentURL
                let onArticlePage = currentURL.map { !vm.isDifferentPageFromItem($0) } ?? true
                vm.navigatedWebURL = onArticlePage ? nil : currentURL
                if onArticlePage {
                    vm.pendingNavigationURL = nil
                }
            },
            onPageFinished: { webView in
                vm.handleArticlePageDidFinish(webView)
            }
        )
        .ignoresSafeArea(edges: .bottom)
        #endif
    }

    // MARK: - Capture FAB

    /// The page the FAB acts on: whatever is actually on screen.
    private var capturePageURL: URL {
        vm.navigatedWebURL ?? currentWebURL ?? url
    }

    private var captureState: ReaderCaptureState {
        guard let capturedItem else { return .unsaved }
        return capturedItem.boards.isEmpty ? .unfiled : .filed
    }

    /// Saved highlights belonging to the page on screen, in stable order.
    /// Resolved through the same item the capture FAB acts on, so a page
    /// reached by following a link shows its own marks — and an unsaved page
    /// shows none, because it has none.
    private var pageHighlights: [String] {
        guard let capturedItem else { return [] }
        return Self.highlightQuotes(from: capturedItem.reflections)
    }

    /// The quotes Reader mode marks for a set of reflections: in reflection
    /// order, trimmed, with reflections that quote nothing left out.
    static func highlightQuotes(from reflections: [ReflectionBlock]) -> [String] {
        reflections
            .sorted { $0.position < $1.position }
            .compactMap { block in
                let quote = (block.highlight ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return quote.isEmpty ? nil : quote
            }
    }

    private var captureFAB: some View {
        ReaderCaptureFAB(
            state: captureState,
            pageKey: capturePageURL.absoluteString
        ) {
            if capturedItem == nil {
                captureCurrentPage()
            }
            showCapturePicker = true
        }
        .padding(20)
        // Arrow on the top edge — the FAB sits at the bottom of the pane, so
        // the picker opens upward into the content it files.
        .popover(isPresented: $showCapturePicker, arrowEdge: .top) {
            if let capturedItem {
                let decision = BoardSuggestionMetadata.decision(from: capturedItem)
                BoardPickerView(
                    boards: boards,
                    mode: .add,
                    chrome: .popover,
                    suggestedName: decision?.suggestedName ?? "",
                    recommendedBoardID: decision?.recommendedBoardID,
                    alternativeBoardIDs: decision?.alternativeBoardIDs ?? [],
                    onSelect: { board in
                        BoardSuggestionMetadata.recordSelection(board, on: capturedItem)
                        ItemViewModel(modelContext: modelContext).assignToBoard(capturedItem, board: board)
                        finishFiling()
                    },
                    onCreate: { title in
                        createAndAssignBoard(named: title, to: capturedItem)
                        finishFiling()
                    }
                )
            }
        }
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
            showFiledConfirmation = false
        }
    }

    /// Re-resolve which library item (if any) backs the page on screen.
    /// Runs on every navigation and after any capture or assignment.
    private func resolveCaptureState() {
        // A confirmation belongs to the page it was earned on.
        showFiledConfirmation = false
        let pageURL = capturePageURL.absoluteString
        if !vm.isDifferentPageFromItem(capturePageURL) {
            capturedItem = vm.item
            return
        }
        let existing = CaptureService(modelContext: modelContext).existingItem(forURL: pageURL)
        capturedItem = existing
        // Arriving at a page that is already in the library is the same trail
        // as capturing it here would have been — record it either way, so the
        // link between the two isn't lost to the accident of having saved the
        // destination on some earlier day.
        if let existing {
            ReadingCapture.recordProvenance(from: vm.item, to: existing, in: modelContext)
        }
    }

    /// Saving while reading is deliberate — straight to the library, active,
    /// skipping inbox triage. Filing happens right after, in the picker.
    private func captureCurrentPage() {
        let (item, _) = ReadingCapture.capturePage(capturePageURL, readFrom: vm.item, in: modelContext)
        capturedItem = item
    }

    private func createAndAssignBoard(named rawTitle: String, to item: Item) {
        let title = BoardSuggestionEngine.cleanedBoardName(rawTitle)
        guard !title.isEmpty else { return }

        let itemViewModel = ItemViewModel(modelContext: modelContext)
        if let existing = boards.first(where: {
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        }) {
            BoardSuggestionMetadata.recordSelection(existing, on: item)
            itemViewModel.assignToBoard(item, board: existing)
        } else {
            let board = Board(title: title)
            modelContext.insert(board)
            BoardSuggestionMetadata.recordSelection(board, on: item)
            itemViewModel.assignToBoard(item, board: board)
        }
    }

    // MARK: - Toolbar Clusters

    /// The one persistent way out of the web pane and back to the item.
    private var overviewButton: some View {
        Button {
            vm.pendingNavigationURL = nil
            vm.navigatedWebURL = nil
            // A selection made in the web pane must not follow the user out:
            // the overview would show the highlight bar over nothing.
            vm.webSelectedText = nil
            vm.webSelectionGeometry = nil
            withAnimation(.easeOut(duration: 0.2)) { vm.showArticleWebView = false }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                // At the narrowest the chevron carries the meaning alone; the
                // word is the first thing worth trading for the domain.
                if onStrip(.overviewLabel) {
                    Text("Overview")
                        .font(.groveMeta)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(Color.textSecondary)
            #if os(iOS)
            .frame(minHeight: LayoutDimensions.minTouchTarget)
            #endif
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back to overview")
        .accessibilityLabel("Back to overview")
    }

    /// Reader-mode typography: size down, size up, serif toggle, column width.
    private var typographyControls: some View {
        HStack(spacing: 6) {
            Button { stepTextSize(-1) } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(readerSizeStep <= ReaderTypographySettings.sizeStepRange.lowerBound)
            .help("Smaller text")
            .accessibilityLabel("Smaller text")

            Button { stepTextSize(1) } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(readerSizeStep >= ReaderTypographySettings.sizeStepRange.upperBound)
            .help("Larger text")
            .accessibilityLabel("Larger text")

            Button {
                readerUseSerif.toggle()
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 11, weight: readerUseSerif ? .semibold : .regular))
                    .foregroundStyle(readerUseSerif ? Color.textSecondary : Color.textMuted)
            }
            .buttonStyle(.plain)
            .help(readerUseSerif ? "Switch to sans-serif" : "Switch to serif")
            .accessibilityLabel(readerUseSerif ? "Switch to sans-serif font" : "Switch to serif font")

            Button {
                readerIsWide.toggle()
            } label: {
                Image(systemName: readerIsWide ? "arrow.right.and.line.vertical.and.arrow.left" : "arrow.left.and.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .help(readerIsWide ? "Narrow column" : "Wide column")
            .accessibilityLabel(readerIsWide ? "Narrow column" : "Wide column")
        }
    }

    /// Live-page zoom. The percentage doubles as the reset target.
    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { vm.zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .help("Zoom out (\u{2318}\u{2212})")
            .accessibilityLabel("Zoom out")
            .disabled(vm.webViewZoomLevel <= 0.5)

            Text("\(vm.zoomPercentage)%")
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 36, alignment: .center)
                .onTapGesture { vm.resetZoom() }
                .help("Reset zoom")

            Button { vm.zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .help("Zoom in (\u{2318}+)")
            .accessibilityLabel("Zoom in")
            .disabled(vm.webViewZoomLevel >= 2.0)
        }
    }

    private var reflectButton: some View {
        Button {
            vm.openReflectionEditor(type: .keyInsight, content: "", highlight: nil, focusTrigger: focusTrigger)
        } label: {
            Label("Reflect", systemImage: "square.and.pencil")
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .help("Open reflection panel")
    }

    private var openInBrowserButton: some View {
        Button {
            #if os(macOS)
            NSWorkspace.shared.open(currentWebURL ?? url)
            #else
            openURL(currentWebURL ?? url)
            #endif
        } label: {
            Image(systemName: "arrow.up.right.square")
                .font(.groveBody)
                .foregroundStyle(Color.textMuted)
        }
        .buttonStyle(.plain)
        .help("Open in browser")
        .accessibilityLabel("Open in browser")
    }

    #if os(macOS)
    private var fullScreenButton: some View {
        Button { toggleFullScreen() } label: {
            Image(systemName: isFullScreen
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textMuted)
        }
        .buttonStyle(.plain)
        .help(isFullScreen ? "Exit Full Screen" : "Enter Full Screen")
        .accessibilityLabel(isFullScreen ? "Exit Full Screen" : "Enter Full Screen")
    }
    #endif

    /// Web history for the page on screen. Works in Reader mode too: the live
    /// page stays mounted underneath, so its history is still the pane's.
    private var webHistoryControls: some View {
        HStack(spacing: 10) {
            Divider().frame(width: 1, height: 12)

            Button { goBackToken += 1 } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(webBackEnabled ? Color.textSecondary : Color.textMuted)
                    #if os(iOS)
                    .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                    #else
                    .frame(width: 12)
                    #endif
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!webBackEnabled)
            .help("Page back")
            .accessibilityLabel("Page back")

            Button { goForwardToken += 1 } label: {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(webForwardEnabled ? Color.textSecondary : Color.textMuted)
                    #if os(iOS)
                    .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                    #else
                    .frame(width: 12)
                    #endif
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!webForwardEnabled)
            .help("Page forward")
            .accessibilityLabel("Page forward")
        }
        .padding(.trailing, 10)
    }

    /// Whether the pane is showing the item's own page rather than something
    /// reached from it. Normalized comparison, so the item's canonical URL and
    /// the URL the web view reports count as the same page.
    private var isOnRootPage: Bool {
        !vm.isDifferentPageFromItem(capturePageURL)
    }

    /// The item this one was harvested from while reading, when there is one.
    /// Only meaningful on the item's own page — once the reader has followed a
    /// link, where *this* page came from is the more useful fact.
    private var provenanceSource: Item? {
        guard isOnRootPage else { return nil }
        return ReadingCapture.provenanceSource(of: vm.item)
    }

    /// Where the page on screen came from. On a page reached by browsing that
    /// is its host; on an item that was itself harvested while reading
    /// something else, the trail back to that something else is the more
    /// interesting provenance, and takes the slot.
    @ViewBuilder
    private var domainLabel: some View {
        if let source = provenanceSource {
            ReaderViaChip(title: source.title) { open(source) }
        } else {
            let pageURL = currentWebURL ?? url
            Text(pageURL.host ?? pageURL.absoluteString)
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(pageURL.absoluteString)
        }
    }

    /// Opens another library item. Prefers the reader's own navigation hook so
    /// the pane swaps in place; falls back to the app-wide open notification
    /// on surfaces that mount the panel without one.
    private func open(_ item: Item) {
        if let navigate = vm.onNavigateToItem {
            navigate(item)
        } else {
            NotificationCenter.default.post(name: .groveOpenItem, object: item.id)
        }
    }

    /// Two named states instead of one icon that showed the destination.
    /// The active segment is marked by the app's left rule, not a filled pill.
    ///
    /// What is lit is what is on screen, never what was asked for: while a
    /// followed link is still being parsed the pane shows the live page, so
    /// ORIGINAL is the honest state even though Reader mode is still the
    /// standing preference and will resume the moment the parse lands.
    private var readerModeControl: some View {
        HStack(spacing: 10) {
            ReaderModeSegment(
                title: "READER",
                isActive: showsReaderContent,
                isAvailable: vm.activeReaderArticle != nil,
                help: vm.activeReaderArticle != nil ? "Reader view" : "Preparing reader view\u{2026}"
            ) { setReaderMode(true) }

            ReaderModeSegment(
                title: "ORIGINAL",
                isActive: !showsReaderContent,
                help: "Original page"
            ) { setReaderMode(false) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page view")
    }

    private func setReaderMode(_ isReader: Bool) {
        guard vm.isReaderMode != isReader else { return }
        withAnimation(.easeOut(duration: 0.2)) { vm.isReaderMode = isReader }
    }

    // MARK: - Reader Settings

    /// Every way the page can be resized or re-set, named. Glyph pairs on the
    /// strip were compact but unreadable — a menu can afford words, and the
    /// strip gets its width back for the things that are about *this* page.
    /// Which half shows follows what is on screen: the type scale for parsed
    /// text, page zoom for the live page.
    private var readerSettingsMenu: some View {
        Menu {
            // Whatever the strip could not seat comes back here, above the
            // reading settings — these are actions, not preferences.
            if inMenu(.readerMode), showsReaderModeControl {
                Picker("View", selection: Binding(
                    get: { showsReaderContent },
                    set: { setReaderMode($0) }
                )) {
                    Text("Reader").tag(true)
                    Text("Original").tag(false)
                }
                .pickerStyle(.inline)
            }

            if inMenu(.reflect) || inMenu(.openInBrowser) || inMenu(.fullScreen) {
                Section {
                    if inMenu(.reflect) {
                        Button("Reflect", systemImage: "square.and.pencil") {
                            vm.openReflectionEditor(type: .keyInsight, content: "", highlight: nil, focusTrigger: focusTrigger)
                        }
                    }

                    if inMenu(.openInBrowser) {
                        Button("Open in Browser", systemImage: "arrow.up.right.square") {
                            #if os(macOS)
                            NSWorkspace.shared.open(currentWebURL ?? url)
                            #else
                            openURL(currentWebURL ?? url)
                            #endif
                        }
                    }

                    #if os(macOS)
                    if inMenu(.fullScreen) {
                        Button(
                            isFullScreen ? "Exit Full Screen" : "Enter Full Screen",
                            systemImage: isFullScreen
                                ? "arrow.down.right.and.arrow.up.left"
                                : "arrow.up.left.and.arrow.down.right"
                        ) {
                            toggleFullScreen()
                        }
                    }
                    #endif
                }
            }

            if showsReaderContent {
                Section("Text Size") {
                    Button("Larger", systemImage: "textformat.size.larger") { stepTextSize(1) }
                        .disabled(readerSizeStep >= ReaderTypographySettings.sizeStepRange.upperBound)
                    Button("Smaller", systemImage: "textformat.size.smaller") { stepTextSize(-1) }
                        .disabled(readerSizeStep <= ReaderTypographySettings.sizeStepRange.lowerBound)
                    Button("Reset", systemImage: "arrow.counterclockwise") { resetTextSize() }
                        .disabled(readerSizeStep == ReaderTypographySettings.defaultSizeStep)
                }

                Picker("Typeface", selection: $readerUseSerif) {
                    Text("Serif").tag(true)
                    Text("Sans-Serif").tag(false)
                }
                .pickerStyle(.inline)

                Picker("Column", selection: $readerIsWide) {
                    Text("Narrow").tag(false)
                    Text("Wide").tag(true)
                }
                .pickerStyle(.inline)
            } else {
                Section("Zoom \u{2014} \(vm.zoomPercentage)%") {
                    Button("Zoom In", systemImage: "plus.magnifyingglass") { vm.zoomIn() }
                        .disabled(vm.webViewZoomLevel >= 2.0)
                    Button("Zoom Out", systemImage: "minus.magnifyingglass") { vm.zoomOut() }
                        .disabled(vm.webViewZoomLevel <= 0.5)
                    Button("Actual Size", systemImage: "arrow.counterclockwise") { resetTextSize() }
                        .disabled(vm.webViewZoomLevel == 1.0)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textMuted)
                #if os(iOS)
                .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                #endif
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Reading settings")
        .accessibilityLabel("Reading settings")
    }

    /// One text-size control for two mechanisms: Reader mode steps the type
    /// scale, the live page steps page zoom. What the keyboard shortcut does is
    /// therefore always what the reader can see.
    private func stepTextSize(_ direction: Int) {
        guard showsReaderContent else {
            if direction > 0 { vm.zoomIn() } else { vm.zoomOut() }
            return
        }
        let range = ReaderTypographySettings.sizeStepRange
        readerSizeStep = min(max(readerSizeStep + direction, range.lowerBound), range.upperBound)
    }

    private func resetTextSize() {
        if showsReaderContent {
            readerSizeStep = ReaderTypographySettings.defaultSizeStep
        } else {
            vm.resetZoom()
        }
    }

    #if os(macOS)
    /// True only for the window this panel is hosted in. Full-screen
    /// notifications are posted for every window, and the panel must not
    /// follow a transition that happened somewhere else.
    private func isHostWindow(_ object: Any?) -> Bool {
        guard let window = object as? NSWindow else { return false }
        return window === hostWindow
    }

    private func toggleFullScreen() {
        (hostWindow ?? NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }

    private static func windowIsFullScreen(_ window: NSWindow?) -> Bool {
        window?.styleMask.contains(.fullScreen) ?? false
    }
    #endif
}

// MARK: - Provenance Chip

/// "← via {source}" in the nav bar's provenance slot: this page is here
/// because of that one. Quiet by default — the trail is context, not a
/// headline — and darkens on hover like every other link in the app.
private struct ReaderViaChip: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    private var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 9, weight: .medium))
                Text("via \(displayTitle)")
                    .font(.groveMeta)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(isHovered ? Color.textSecondary : Color.textMuted)
            .frame(maxWidth: 220, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(displayTitle)
        .accessibilityLabel("Reached from \(displayTitle)")
        .accessibilityHint("Opens the item this page was saved from.")
    }
}

// MARK: - Reader / Original Segment

/// One segment of the Reader | Original control. Named state, never a
/// destination: the segment that is lit is the mode you are in. Selection is
/// the app's 2pt left rule; hover darkens the ink rather than adding a fill.
private struct ReaderModeSegment: View {
    let title: String
    let isActive: Bool
    /// False while a followed page is still parsing: the segment is visible
    /// (the control shouldn't blink) but dimmed and inert, so a tap that
    /// could do nothing visible does nothing at all.
    var isAvailable: Bool = true
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Rectangle()
                    .fill(Color.textPrimary)
                    .frame(width: 2, height: 11)
                    .opacity(isActive ? 1 : 0)

                Text(title)
                    .font(.groveSectionHeader)
                    .tracking(0.8)
                    .foregroundStyle(ink)
                    // Without this a squeezed strip breaks the word down the
                    // column, one letter per line.
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 3)
            #if os(iOS)
            .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
            #endif
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.45)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : [.isButton])
    }

    private var ink: Color {
        if isActive { return .textPrimary }
        return isHovered ? .textSecondary : .textMuted
    }
}

// MARK: - Highlight Action Bar

/// The full selection overlay (bar + highlight action + transition) used by
/// both macOS reader surfaces so their selection handling can't drift.
///
/// With geometry the bar floats beside the selection it acts on; without it —
/// native content, which reports no rect — it keeps the old pane-bottom
/// placement.
struct HighlightActionBarOverlay: View {
    let vm: ItemReaderViewModel
    let selection: String
    var selectionGeometry: WebSelectionGeometry? = nil
    /// Fired after the highlight is written. Writing on a page reached by
    /// browsing captures that page into the library, so whoever owns the page's
    /// identity (the capture FAB, the highlight marks) needs to re-resolve.
    var onWrite: (() -> Void)? = nil

    var body: some View {
        if let selectionGeometry {
            SelectionAnchorLayout(geometry: selectionGeometry) {
                bar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        } else {
            bar
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var bar: some View {
        HighlightActionBar(
            onHighlight: {
                vm.addHighlight(selection)
                onWrite?()
            },
            onRemember: {
                vm.openFlashcardEditor(quote: selection)
                onWrite?()
            }
        )
    }
}

// MARK: - Selection Anchoring

/// Places a single floating control beside a web-view text selection.
///
/// A `Layout` rather than a GeometryReader + measured state: it needs both the
/// pane size and the control's own size to clamp, and the layout pass hands it
/// both without a second render. Only the control is hit-testable — the rest of
/// the pane keeps passing clicks through to the page.
struct SelectionAnchorLayout: Layout {
    var geometry: WebSelectionGeometry

    /// Keep-out from the pane edges.
    static let margin: CGFloat = 12
    /// Breathing room between the selection and the bar.
    static let gap: CGFloat = 8
    /// A selection this close to the top has no room above it; flip below.
    static let flipThreshold: CGFloat = 60

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let barSize = subview.sizeThatFits(.unspecified)
        let rect = geometry.rect(inPaneOfWidth: bounds.width)
        let origin = Self.origin(barSize: barSize, selection: rect, pane: bounds.size)
        subview.place(
            at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
            anchor: .topLeading,
            proposal: ProposedViewSize(barSize)
        )
    }

    /// Centered on the selection, clamped inside the pane, above it when there
    /// is room and below it when there isn't.
    static func origin(barSize: CGSize, selection: CGRect, pane: CGSize) -> CGPoint {
        var x = selection.midX - barSize.width / 2
        let maxX = pane.width - margin - barSize.width
        x = maxX >= margin ? min(max(x, margin), maxX) : (pane.width - barSize.width) / 2

        var y = selection.minY - gap - barSize.height
        if selection.minY < flipThreshold || y < margin {
            y = selection.maxY + gap
        }
        let maxY = pane.height - margin - barSize.height
        y = maxY >= margin ? min(max(y, margin), maxY) : (pane.height - barSize.height) / 2

        return CGPoint(x: x, y: y)
    }
}

/// Quiet floating pill shown while a text selection is active in the reader.
/// Save a passage as a highlight or use it to make a flashcard.
/// Shared by the desktop web panel and the iOS mobile reader.
struct HighlightActionBar: View {
    var onHighlight: () -> Void
    var onRemember: (() -> Void)? = nil

    #if os(iOS)
    private static let minTargetSize: CGFloat = 44
    #else
    private static let minTargetSize: CGFloat = 0
    #endif

    var body: some View {
        HStack(spacing: 0) {
            barButton(
                title: "Highlight",
                systemImage: "highlighter",
                action: onHighlight
            )
            .help("Save selection as a highlight")
            if let onRemember {
                Divider().frame(height: 16)
                barButton(title: "Remember", systemImage: "rectangle.on.rectangle", action: onRemember)
                    .help("Make a flashcard from this passage")
            }
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private func barButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.groveMeta)
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: Self.minTargetSize, minHeight: Self.minTargetSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Find Bar

struct ItemReaderFindBar: View {
    @Bindable var vm: ItemReaderViewModel

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                TextField("Find in article...", text: Binding(
                    get: { vm.findQuery },
                    set: { vm.findQuery = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.groveMeta)
                .onSubmit { vm.findForwardToken += 1 }
                #if os(macOS)
                .onExitCommand { vm.closeFindBar() }
                #endif
                if !vm.findQuery.isEmpty {
                    Text("\(vm.findCurrentMatch)/\(vm.findMatchCount)")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.bgCard)
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )

            Button {
                vm.findBackwardToken += 1
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Previous match")
            .disabled(vm.findQuery.isEmpty)

            Button {
                vm.findForwardToken += 1
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Next match")
            .disabled(vm.findQuery.isEmpty)

            Button {
                vm.closeFindBar()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Close find bar (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.bgCard)

        Divider()
    }
}
