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

    /// True when the reader has navigated away from the item's own page.
    private var isBrowsingLinkedPage: Bool {
        guard let currentWebURL else { return false }
        return ReadingCapture.isDifferentPage(currentWebURL, from: item)
    }

    /// The item reflections and highlights belong to: the linked page once
    /// it has been captured, otherwise the item being read.
    private var readingItem: Item {
        capturedPageItem ?? item
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
        return resolvedSourceURL(from: item.sourceURL)
    }

    var body: some View {
        mainLayout
            .onAppear {
                // iPad: auto-open reflections panel for article+notes reading experience
                if usesSidePanel && rightPanel == .none {
                    rightPanel = .reflections
                }
            }
            .navigationTitle(item.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .sheet(isPresented: $showReflections) {
                reflectionSheetContent
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
                    .overlay(alignment: .bottom) { highlightActionOverlay }
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
            .overlay(alignment: .bottom) { highlightActionOverlay }
        }
    }

    // MARK: - Highlight actions

    private var trimmedSelection: String? {
        guard let text = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    @ViewBuilder
    private var highlightActionOverlay: some View {
        if item.type != .note, let selection = trimmedSelection {
            HighlightActionBar(
                onHighlight: { addHighlight(selection) },
                onHighlightAndReflect: { highlightAndReflect(selection) }
            )
            .padding(.bottom, Spacing.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: 0.15), value: trimmedSelection != nil)
        }
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

    private func highlightAndReflect(_ text: String) {
        let block = addHighlight(text)
        pendingEditBlock = block
        if usesSidePanel {
            withAnimation { rightPanel = .reflections }
        } else {
            if horizontalSizeClass == .regular {
                reflectionDetent = .large
            }
            showReflections = true
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
            articleContent
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
                .ignoresSafeArea(edges: .bottom)
            }
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
            } else if isBrowsingLinkedPage, capturedPageItem == nil {
                Button {
                    saveCurrentPage()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: LayoutDimensions.minTouchTarget, height: LayoutDimensions.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save page to library")
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
            // Zoom controls (articles only)
            if item.type != .note {
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
            if item.type != .note {
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
