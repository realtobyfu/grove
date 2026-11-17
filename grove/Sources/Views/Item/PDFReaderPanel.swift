import SwiftUI
import SwiftData
import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - PDF Reader Panel

/// The reading surface for an item whose source is a document.
///
/// It stands exactly where the web panel stands, so the notes column beside it
/// never moves. A PDF routed into a web view *looks* fine — WebKit's plugin
/// renders it — but selection, find, Reader mode and reading progress are all
/// silently dead there, which is the whole reason this exists.
struct PDFReaderPanel: View {
    let item: Item
    /// The reader's find session, on hosts that offer find-in-document (the
    /// macOS reader). Nil elsewhere, and the pane then has no find bar.
    var find: ReaderFindSession? = nil
    /// Back to the item overview. Absent on surfaces that already carry their
    /// own navigation (iOS pushes the reader as a screen of its own).
    var onExit: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum LoadState {
        case loading
        case loaded(PDFDocument)
        case failed
    }

    @State private var state: LoadState = .loading
    @State private var currentPageIndex = 0
    @State private var pageCount = 0
    /// Mirrors ItemReaderViewModel.updateReadingProgress: the model is only
    /// dirtied past a meaningful delta, so paging through a long document
    /// doesn't fan out an observation invalidation per page. Seeded from the
    /// stored value in `load()`, so the first write has to genuinely differ
    /// from what is already persisted.
    @State private var lastSavedProgress: Double = -1

    private var sourceURL: URL? {
        resolvedSourceURL(from: item.sourceURL)
    }

    /// Persisted 0–1 progress, in the same format the web reader writes.
    private var storedProgress: Double {
        item.readingProgress
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider()
            // Same place as in the web panel: under the pane's own strip, so
            // it is still there when full screen hides the window toolbar.
            if let find, find.isPresented {
                ReaderFindBar(find: find, placeholder: "Find in document")
                    .transition(ReaderFindBar.revealTransition(reduceMotion: reduceMotion))
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.bgPrimary)
        .task(id: item.id) { await load() }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack(spacing: Spacing.sm) {
            if let onExit {
                Button {
                    onExit()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                        Text("Overview")
                            .font(.groveMeta)
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

            Text(sourceURL?.lastPathComponent ?? item.title)
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if pageCount > 0 {
                Text("\(currentPageIndex + 1) / \(pageCount)")
                    .font(.groveMeta)
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityLabel("Page \(currentPageIndex + 1) of \(pageCount)")
            }

            if sourceURL != nil {
                Button {
                    openInBrowser()
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.groveBody)
                        .foregroundStyle(Color.textMuted)
                        #if os(iOS)
                        .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                        #endif
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in browser")
                .accessibilityLabel("Open in browser")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xsm)
        .background(Color.bgCard)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            statusColumn {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.textSecondary)
                Text("Fetching document\u{2026}")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }
        case .failed:
            statusColumn {
                Text("This document could not be opened.")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                if sourceURL != nil {
                    Button {
                        openInBrowser()
                    } label: {
                        Text("Open in browser")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                            .underline()
                            #if os(iOS)
                            .frame(minHeight: LayoutDimensions.minTouchTarget)
                            #endif
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .loaded(let document):
            PDFDocumentView(
                document: document,
                initialProgress: storedProgress,
                onPageChanged: { index, count, persist in
                    currentPageIndex = index
                    pageCount = count
                    // Page changes during the restore settle are PDFKit's own
                    // relayout, not the reader's; persisting them would write
                    // page one over the place they left off.
                    if persist {
                        recordProgress(pageIndex: index, pageCount: count)
                    }
                },
                findQuery: find?.activeQuery ?? "",
                findForwardToken: find?.forwardToken ?? 0,
                findBackwardToken: find?.backwardToken ?? 0,
                onFindResult: { query, status in
                    find?.report(status, for: query)
                }
            )
        }
    }

    @ViewBuilder
    private func statusColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: Spacing.sm) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }

    // MARK: - Loading

    /// The enricher normally caches the file while it pulls title and cover
    /// out of it, so opening is usually a disk read. Downloading here is the
    /// fallback for an item captured before that ran, or whose cache was
    /// cleared.
    private func load() async {
        lastSavedProgress = storedProgress

        if let cached = PDFMetadataService.cachedFileURL(itemID: item.id),
           let document = PDFDocument(url: cached) {
            state = .loaded(document)
            return
        }

        guard let url = sourceURL else {
            state = .failed
            return
        }

        state = .loading
        guard let extracted = await PDFMetadataService.downloadAndExtract(url: url, itemID: item.id),
              let document = PDFDocument(url: extracted.cachedFileURL) else {
            state = .failed
            return
        }

        if !item.isPDFCached {
            item.isPDFCached = true
            try? modelContext.save()
        }
        state = .loaded(document)
    }

    // MARK: - Reading Progress

    /// Page position as the same 0–1 fraction the web reader stores, so a
    /// document and an article report their progress in one currency.
    private func recordProgress(pageIndex: Int, pageCount: Int) {
        guard pageCount > 0 else { return }
        let fraction = min(max(Double(pageIndex) / Double(max(pageCount - 1, 1)), 0), 1)
        guard abs(fraction - lastSavedProgress) >= 0.05 || fraction >= 0.995 else { return }
        lastSavedProgress = fraction
        item.readingProgress = fraction
        try? modelContext.save()
    }

    // MARK: - Actions

    private func openInBrowser() {
        guard let sourceURL else { return }
        #if os(macOS)
        NSWorkspace.shared.open(sourceURL)
        #else
        openURL(sourceURL)
        #endif
    }
}

// MARK: - PDFView Representable

/// PDFKit's view, in one representable for both platforms: continuous vertical
/// scrolling on the reader's own background, with no page shadows — the app has
/// no drop shadows anywhere else either.
private struct PDFDocumentView {
    let document: PDFDocument
    /// 0–1 fraction to open at, restored to the nearest page.
    let initialProgress: Double
    /// `(pageIndex, pageCount, persist)`. `persist` is false while the restore
    /// is still settling — the page counter may follow those reports, reading
    /// progress must not.
    var onPageChanged: ((Int, Int, Bool) -> Void)?
    /// Find-in-document: the query to show ("" for none) and the tokens that
    /// step to the next / previous match. Results come back as
    /// `(query, status)`.
    var findQuery: String = ""
    var findForwardToken: Int = 0
    var findBackwardToken: Int = 0
    var onFindResult: ((String, ReaderFind.Status) -> Void)?

    @MainActor
    fileprivate func makePDFView(coordinator: Coordinator) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = Self.paneBackground
        #if os(macOS)
        view.pageShadowsEnabled = false
        #endif
        view.document = document

        coordinator.onPageChanged = onPageChanged
        coordinator.onFindResult = onFindResult
        coordinator.attach(view)
        coordinator.restore(progress: initialProgress, in: view)
        return view
    }

    @MainActor
    fileprivate func updatePDFView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.onPageChanged = onPageChanged
        coordinator.onFindResult = onFindResult
        if view.document !== document {
            view.document = document
            coordinator.restore(progress: initialProgress, in: view)
            // Matches found in the old document mean nothing in this one.
            coordinator.resetFind()
        }
        coordinator.updateFind(
            in: view,
            query: findQuery,
            forwardToken: findForwardToken,
            backwardToken: findBackwardToken
        )
    }

    #if os(macOS)
    private static var paneBackground: NSColor {
        NSColor(named: "bgPrimary") ?? .textBackgroundColor
    }
    #else
    private static var paneBackground: UIColor {
        UIColor(named: "bgPrimary") ?? .systemBackground
    }
    #endif

    // MARK: Coordinator

    @MainActor
    final class Coordinator {
        var onPageChanged: ((Int, Int, Bool) -> Void)?
        private weak var view: PDFView?
        private var observer: NSObjectProtocol?
        private var pendingRestoreIndex: Int?
        private var didRestore = false

        /// Reading progress is only written once the restore has settled:
        /// the corrective re-jump has run *and* enough time has passed since
        /// mount that the report can only be the reader's own doing. PDFKit
        /// emits a burst of page changes while it lays the document out, and
        /// every one of them looks like "the user is on page one".
        private static let settleWindow: TimeInterval = 0.6
        private var mountedAt = Date()
        private var didFinishRestoreJump = false

        private var mayPersistProgress: Bool {
            didFinishRestoreJump && Date().timeIntervalSince(mountedAt) >= Self.settleWindow
        }

        func attach(_ view: PDFView) {
            self.view = view
            guard observer == nil else { return }
            mountedAt = Date()
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportPage() }
            }
        }

        func detach() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            view = nil
        }

        /// Opens at the saved place, then repeats the jump once after the
        /// first layout pass: PDFKit re-lays out its scroll view when the
        /// document is first displayed and otherwise snaps back to page one.
        func restore(progress: Double, in view: PDFView) {
            guard !didRestore,
                  let document = view.document,
                  document.pageCount > 0 else { return }
            didRestore = true

            let lastIndex = document.pageCount - 1
            let target = Int((progress * Double(max(lastIndex, 1))).rounded())
            let clamped = min(max(target, 0), lastIndex)

            if clamped > 0 {
                pendingRestoreIndex = clamped
                go(to: clamped, in: view)
                MainActorTaskScheduler.schedule(after: .milliseconds(150)) { [weak self] in
                    self?.applyPendingRestore()
                }
            } else {
                // Nothing to re-jump to; only the settle window stands between
                // mount and the first honest report.
                didFinishRestoreJump = true
            }
            reportPage()
        }

        private func applyPendingRestore() {
            defer { didFinishRestoreJump = true }
            guard let index = pendingRestoreIndex, let view else { return }
            pendingRestoreIndex = nil
            if currentIndex(in: view) != index {
                go(to: index, in: view)
            }
            reportPage()
        }

        private func go(to index: Int, in view: PDFView) {
            guard let page = view.document?.page(at: index) else { return }
            view.go(to: page)
        }

        private func currentIndex(in view: PDFView) -> Int {
            guard let document = view.document, let page = view.currentPage else { return 0 }
            return document.index(for: page)
        }

        private func reportPage() {
            guard let view, let document = view.document else { return }
            onPageChanged?(currentIndex(in: view), document.pageCount, mayPersistProgress)
        }

        // MARK: Find

        /// `(query, status)`. Delivered a turn after the view update that
        /// asked for the search, never from inside it.
        var onFindResult: ((String, ReaderFind.Status) -> Void)?
        private var findQuery = ""
        private var findForwardToken = 0
        private var findBackwardToken = 0
        /// Every match of `findQuery`, in document order, from PDFKit's own
        /// search. Owning the whole list is what lets this surface report a
        /// position ("3 of 12") and stand behind it.
        private var findMatches: [PDFSelection] = []
        private var findIndex: Int?

        private enum FindAction: Sendable {
            case search(String)
            case step(forward: Bool)
            case clear
        }

        /// Forget the current search, so the next update runs it afresh.
        func resetFind() {
            findQuery = ""
            findMatches = []
            findIndex = nil
        }

        func updateFind(in view: PDFView, query: String, forwardToken: Int, backwardToken: Int) {
            let queryChanged = query != findQuery
            let steppedForward = forwardToken != findForwardToken
            let steppedBackward = backwardToken != findBackwardToken
            findQuery = query
            findForwardToken = forwardToken
            findBackwardToken = backwardToken

            let action: FindAction
            if queryChanged {
                action = query.isEmpty ? .clear : .search(query)
            } else if !query.isEmpty, steppedForward || steppedBackward {
                action = .step(forward: steppedForward)
            } else {
                return
            }
            // A turn later: a search moves the selection and the page, both of
            // which report back into view state, and none of that may happen
            // inside the update pass that asked for it.
            Task { @MainActor [weak self, weak view] in
                guard let self, let view else { return }
                self.performFind(action, in: view)
            }
        }

        private func performFind(_ action: FindAction, in view: PDFView) {
            switch action {
            case .clear:
                // Find is over: drop the match it left selected.
                let hadMatch = findIndex != nil
                findMatches = []
                findIndex = nil
                if hadMatch { view.clearSelection() }

            case .search(let query):
                // Superseded while it waited its turn.
                guard query == findQuery else { return }
                let hadMatch = findIndex != nil
                findMatches = []
                findIndex = nil
                guard let document = view.document else { return }
                findMatches = document.findString(query, withOptions: [.caseInsensitive])
                guard !findMatches.isEmpty else {
                    if hadMatch { view.clearSelection() }
                    onFindResult?(query, .noMatches)
                    return
                }
                // Start from where the reader is, not from page one.
                let currentPage = currentIndex(in: view)
                let fromHere = findMatches.firstIndex { selection in
                    guard let page = selection.pages.first else { return false }
                    return document.index(for: page) >= currentPage
                }
                findIndex = fromHere ?? 0
                revealCurrentMatch(in: view)

            case .step(let forward):
                guard !findMatches.isEmpty else { return }
                findIndex = ReaderFind.steppedIndex(
                    from: findIndex,
                    count: findMatches.count,
                    forward: forward
                )
                revealCurrentMatch(in: view)
            }
        }

        /// Selects the current match, scrolls to it and reports its position.
        private func revealCurrentMatch(in view: PDFView) {
            guard let findIndex, findMatches.indices.contains(findIndex) else { return }
            let selection = findMatches[findIndex]
            view.setCurrentSelection(selection, animate: false)
            view.go(to: selection)
            onFindResult?(findQuery, .matches(count: findMatches.count, current: findIndex + 1))
        }
    }
}

#if os(macOS)
extension PDFDocumentView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        makePDFView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        updatePDFView(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }
}
#else
extension PDFDocumentView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        makePDFView(coordinator: context.coordinator)
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        updatePDFView(uiView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }
}
#endif
