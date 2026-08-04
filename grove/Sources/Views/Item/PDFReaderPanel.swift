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
    /// Back to the item overview. Absent on surfaces that already carry their
    /// own navigation (iOS pushes the reader as a screen of its own).
    var onExit: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

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
        Double(item.metadata["readingProgress"] ?? "") ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.bgPrimary)
        .task(id: item.id) { await load() }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        HStack(spacing: 10) {
            if let onExit {
                Button {
                    onExit()
                } label: {
                    HStack(spacing: 4) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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

        if item.metadata["pdfCached"] != "true" {
            item.metadata["pdfCached"] = "true"
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
        item.metadata["readingProgress"] = String(format: "%.3f", fraction)
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
        coordinator.attach(view)
        coordinator.restore(progress: initialProgress, in: view)
        return view
    }

    @MainActor
    fileprivate func updatePDFView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.onPageChanged = onPageChanged
        if view.document !== document {
            view.document = document
            coordinator.restore(progress: initialProgress, in: view)
        }
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
