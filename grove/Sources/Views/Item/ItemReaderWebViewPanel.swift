import SwiftUI
import SwiftData
import WebKit

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
    @State private var justSaved = false
    /// Set when a Reader-mode link click dropped us into Original mode;
    /// navigating back to the article's own page restores Reader mode.
    @State private var returnToReaderOnArticle = false

    // Reader typography (persisted app-wide)
    @AppStorage(ReaderTypographySettings.sizeStepKey) private var readerSizeStep = 1
    @AppStorage(ReaderTypographySettings.isWideKey) private var readerIsWide = false
    @AppStorage(ReaderTypographySettings.useSerifKey) private var readerUseSerif = true

    private var readerTypography: ReaderTypographySettings {
        ReaderTypographySettings(sizeStep: readerSizeStep, isWide: readerIsWide, useSerif: readerUseSerif)
    }

    private var showsReaderContent: Bool {
        vm.isReaderMode && vm.readerArticle != nil
    }

    /// Back can walk web history, or fall through to the article's own
    /// page when the pane mounted directly on a link target.
    private var webBackEnabled: Bool {
        guard !showsReaderContent else { return false }
        if canGoBack { return true }
        if let current = currentWebURL, current.absoluteString != url.absoluteString { return true }
        return false
    }

    private var webForwardEnabled: Bool {
        !showsReaderContent && canGoForward
    }

    /// Non-empty trimmed selection from either web mode, or nil.
    var body: some View {
        VStack(spacing: 0) {
            // Slim navigation bar
            HStack(spacing: 10) {
                Button {
                    vm.pendingNavigationURL = nil
                    vm.navigatedWebURL = nil
                    returnToReaderOnArticle = false
                    withAnimation(.easeOut(duration: 0.2)) { vm.showArticleWebView = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                        Text("Overview")
                            .font(.groveMeta)
                    }
                    .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)

                Divider().frame(height: 12)

                // Browser back/forward — always present so the bar reads
                // the same in both modes; inert while Reader mode is
                // showing (no web history to walk).
                Button { goBackToken += 1 } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(webBackEnabled ? Color.textSecondary : Color.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(!webBackEnabled)
                .help("Back")

                Button { goForwardToken += 1 } label: {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(webForwardEnabled ? Color.textSecondary : Color.textMuted)
                }
                .buttonStyle(.plain)
                .disabled(!webForwardEnabled)
                .help("Forward")

                Divider().frame(height: 12)

                Text((currentWebURL ?? url).host ?? (currentWebURL ?? url).absoluteString)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if showsReaderContent {
                    typographyControls
                } else {
                    zoomControls
                }

                Divider().frame(height: 12)

                boardsMenu

                if vm.readerArticle != nil {
                    Divider().frame(height: 12)

                    Button {
                        returnToReaderOnArticle = false
                        withAnimation(.easeOut(duration: 0.2)) { vm.isReaderMode.toggle() }
                    } label: {
                        Image(systemName: vm.isReaderMode ? "globe" : "doc.plaintext")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(vm.isReaderMode ? "Show original page" : "Show reader view")
                    .accessibilityLabel(vm.isReaderMode ? "Show original page" : "Show reader view")
                }

                Divider().frame(height: 12)

                Button {
                    vm.openReflectionEditor(type: .keyInsight, content: "", highlight: nil, focusTrigger: focusTrigger)
                } label: {
                    Label("Reflect", systemImage: "square.and.pencil")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
                .help("Open reflection panel")

                if vm.showAutoCaptureIndicator || justSaved {
                    // Inline confirmation for saves (explicit or capture-on-write).
                    Label("Saved", systemImage: "checkmark.circle")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                        .transition(.opacity)
                } else if !showsReaderContent,
                   let navigatedURL = currentWebURL, navigatedURL.absoluteString != url.absoluteString {
                    Button {
                        let service = CaptureService(modelContext: modelContext)
                        let (item, _) = service.captureItemDetailed(input: navigatedURL.absoluteString)
                        // Saving while reading is deliberate — straight to
                        // the library, unfiled, skipping inbox triage.
                        if item.status == .inbox {
                            item.status = .active
                        }
                        if vm.item.isNewsletterIssue {
                            vm.item.isFeedIssueRead = true
                        }
                        try? modelContext.save()
                        justSaved = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            justSaved = false
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.groveBody)
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Save page to library")
                }

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
                .help("Open in Browser")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.bgCard)
            Divider()

            if vm.showFindBar && !showsReaderContent {
                ItemReaderFindBar(vm: vm)
            }

            ZStack(alignment: .bottom) {
                if showsReaderContent, let article = vm.readerArticle {
                    readerContent(article: article)
                } else {
                    originalContent
                }

                if let selection = vm.highlightableSelection {
                    HighlightActionBarOverlay(vm: vm, selection: selection, focusTrigger: focusTrigger)
                }
            }
            .animation(.easeOut(duration: 0.15), value: vm.highlightableSelection != nil)
        }
        .task(id: url) {
            // Drop any stale scroll-to-text query from a previous panel
            // session so a freshly mounted web view doesn't auto-scroll.
            vm.scrollToTextQuery = ""
            vm.navigatedWebURL = nil
            vm.loadCachedReaderArticleIfAvailable()
        }
        #if os(macOS)
        .background {
            // Hidden buttons for keyboard shortcuts
            Group {
                Button("") { vm.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("") { vm.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("") { vm.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
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
            onTextSelected: { text in
                vm.webSelectedText = text
                onTextSelected?(text)
            },
            onScrollProgress: { fraction in
                vm.updateReadingProgress(fraction)
            },
            onOpenExternalLink: { linkURL in
                // Links stay inside the reader: drop to the web panel and
                // navigate there. "Open in Browser" remains the escape hatch.
                vm.pendingNavigationURL = linkURL
                vm.pendingNavigationToken += 1
                returnToReaderOnArticle = true
                withAnimation(.easeOut(duration: 0.15)) { vm.isReaderMode = false }
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
                canGoBack = canBack
                canGoForward = canFwd
                currentWebURL = currentURL
                // Mirror into the VM so capture-on-write knows what page
                // a reflection belongs to.
                let onArticlePage = currentURL?.absoluteString == url.absoluteString
                vm.navigatedWebURL = onArticlePage ? nil : currentURL
                // Coming back to the article after a Reader-mode link
                // click returns to Reader mode — the detour is over.
                if onArticlePage, returnToReaderOnArticle {
                    returnToReaderOnArticle = false
                    vm.pendingNavigationURL = nil
                    if vm.readerArticle != nil {
                        withAnimation(.easeOut(duration: 0.15)) { vm.isReaderMode = true }
                    }
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
            findQuery: vm.findQuery,
            findForwardToken: vm.findForwardToken,
            findBackwardToken: vm.findBackwardToken,
            onFindResult: { current, total in
                vm.findCurrentMatch = current
                vm.findMatchCount = total
            },
            zoomLevel: vm.webViewZoomLevel,
            scrollToTextQuery: vm.scrollToTextQuery,
            scrollToTextToken: vm.scrollToTextToken
        )
        .ignoresSafeArea(edges: .bottom)
        #endif
    }

    // MARK: - Toolbar Clusters

    /// "+" menu: file this article into boards without leaving the reader.
    private var boardsMenu: some View {
        Menu {
            ForEach(boards.filter { !$0.isSmart }) { board in
                Toggle(isOn: Binding(
                    get: { vm.item.boards.contains { $0.id == board.id } },
                    set: { isOn in
                        let itemViewModel = ItemViewModel(modelContext: modelContext)
                        if isOn {
                            itemViewModel.assignToBoard(vm.item, board: board)
                        } else {
                            itemViewModel.removeFromBoard(vm.item, board: board)
                        }
                    }
                )) {
                    Label(board.title, systemImage: board.icon ?? "folder")
                }
            }
            if boards.allSatisfy(\.isSmart) {
                Text("No boards yet")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(vm.item.boards.isEmpty ? Color.textMuted : Color.textSecondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add to board")
        .accessibilityLabel("Add to board")
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { vm.zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .help("Zoom out (⌘−)")
            .disabled(vm.webViewZoomLevel <= 0.5)

            Text("\(vm.zoomPercentage)%")
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .center)
                .onTapGesture { vm.resetZoom() }
                .help("Reset zoom")

            Button { vm.zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .help("Zoom in (⌘+)")
            .disabled(vm.webViewZoomLevel >= 2.0)
        }
    }

    private var typographyControls: some View {
        HStack(spacing: 6) {
            Button {
                readerSizeStep = max(readerSizeStep - 1, ReaderTypographySettings.sizeStepRange.lowerBound)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(readerSizeStep <= ReaderTypographySettings.sizeStepRange.lowerBound)
            .help("Smaller text")
            .accessibilityLabel("Smaller text")

            Button {
                readerSizeStep = min(readerSizeStep + 1, ReaderTypographySettings.sizeStepRange.upperBound)
            } label: {
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
}

// MARK: - Highlight Action Bar

/// The full bottom overlay (bar + highlight/reflect actions + transition) used
/// by both macOS reader surfaces so their selection handling can't drift.
struct HighlightActionBarOverlay: View {
    let vm: ItemReaderViewModel
    let selection: String
    let focusTrigger: () -> Void

    var body: some View {
        HighlightActionBar(
            onHighlight: { vm.addHighlight(selection) },
            onHighlightAndReflect: {
                vm.webSelectedText = nil
                vm.openReflectionEditor(
                    type: .keyInsight,
                    content: "",
                    highlight: selection,
                    focusTrigger: focusTrigger
                )
            }
        )
        .padding(.bottom, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Quiet floating bar shown while a text selection is active in the reader.
/// Offers saving the selection as a highlight, optionally with a reflection.
/// Shared by the desktop web panel and the iOS mobile reader.
struct HighlightActionBar: View {
    var onHighlight: () -> Void
    var onHighlightAndReflect: () -> Void

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

            Divider()
                .frame(height: 16)

            barButton(
                title: "Highlight & Reflect",
                systemImage: "square.and.pencil",
                action: onHighlightAndReflect
            )
            .help("Save selection and write a reflection")
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
