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
    @State private var navigateToChat: Conversation?
    @State private var reflectionDetent: PresentationDetent = .medium
    @State private var zoomLevel: CGFloat = 1.0
    @FocusState private var findBarFocused: Bool

    private var usesSidePanel: Bool {
        horizontalSizeClass == .regular && !preferFullScreenReaderExperience
    }

    private var isReflectionsPanelOpen: Bool { rightPanel == .reflections }
    private var isChatPanelOpen: Bool {
        if case .chat = rightPanel { return true }
        return false
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
                let panelWidth = min(max(geo.size.width * 0.4, 320), 480)
                HStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        contentView
                        if showFindBar {
                            findBar
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    rightPanelContent
                        .frame(width: panelWidth)
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
        if let urlString = item.sourceURL, let url = URL(string: urlString) {
            #if os(iOS)
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
                zoomLevel: zoomLevel
            )
            .ignoresSafeArea(edges: .bottom)
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
        if let urlString = item.sourceURL, let url = URL(string: urlString) {
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
        if horizontalSizeClass == .regular {
            MobileReflectionSheet(item: item)
                .frame(minWidth: 400)
                #if os(iOS)
                .presentationDetents([.large], selection: $reflectionDetent)
                .presentationDragIndicator(.visible)
                #endif
        } else {
            MobileReflectionSheet(item: item)
                #if os(iOS)
                .presentationDetents([.medium, .large], selection: $reflectionDetent)
                .presentationDragIndicator(.visible)
                #endif
        }
    }

    // MARK: - Right panel content (iPad)

    @ViewBuilder
    private var rightPanelContent: some View {
        switch rightPanel {
        case .none:
            EmptyView()
        case .reflections:
            MobileReflectionSheet(item: item, onDismiss: {
                withAnimation { rightPanel = .none }
            })
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
