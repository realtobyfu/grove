#if os(macOS)
import Foundation
import WebKit

/// Find-in-article for one macOS web view, on WebKit's own find.
///
/// `WKWebView.find` shows a match by selecting it and scrolling it into view;
/// it never touches the document. That is the point of using it: Reader mode
/// anchors saved highlights by text offsets into the DOM, and a find that
/// wrapped its matches in elements would shift them.
///
/// Both macOS web surfaces — `ReaderModeWebView` and `ArticleWebView` — own
/// one of these on their coordinator and feed it the same three values from
/// `updateNSView`: the query to show ("" for none) and the two step tokens.
@MainActor
final class ReaderWebFindDriver {
    private enum Step {
        /// A new query, or the same query on a newly loaded document.
        case fresh
        case next
        case previous
    }

    /// `(query, status)`. Only ever called from a WebKit completion handler,
    /// never synchronously inside a view update.
    var onResult: ((String, ReaderFind.Status) -> Void)?

    private var query = ""
    private var forwardToken = 0
    private var backwardToken = 0
    /// False between a load the owner announced and its `didFinish`. Searching
    /// a document that is not there yet would report "No matches" for a page
    /// that is merely late.
    private var documentReady = true
    /// Bumped by every search and every clear; a completion handler that finds
    /// it has moved on belongs to a search nobody is waiting for any more.
    private var generation = 0
    /// The document's rendered text, folded for counting. Fetched once per
    /// document per find session rather than once per keystroke.
    private var foldedPageText: String?
    /// Occurrences of `query` in the current document, once counted.
    private var matchCount: Int?

    // MARK: - Document Lifecycle

    /// The owner is about to replace the document (Reader mode loading an
    /// article). Searches wait for `documentDidFinish`.
    func documentWillLoad() {
        documentReady = false
        generation += 1
        foldedPageText = nil
        matchCount = nil
    }

    /// A document finished loading. A query that is still up runs against it:
    /// the bar was open when the page arrived, or the reader followed a link.
    func documentDidFinish(in webView: WKWebView) {
        documentReady = true
        foldedPageText = nil
        matchCount = nil
        guard !query.isEmpty else { return }
        run(.fresh, in: webView)
    }

    // MARK: - Driving

    func update(in webView: WKWebView, query: String, forwardToken: Int, backwardToken: Int) {
        let previousQuery = self.query
        let steppedForward = forwardToken != self.forwardToken
        let steppedBackward = backwardToken != self.backwardToken
        self.query = query
        self.forwardToken = forwardToken
        self.backwardToken = backwardToken

        if query != previousQuery {
            matchCount = nil
            if query.isEmpty {
                // Find is over for this surface: the bar closed, the field was
                // emptied, or the other web view took the screen.
                generation += 1
                foldedPageText = nil
                clearMatchSelection(for: previousQuery, in: webView)
            } else if documentReady {
                run(.fresh, in: webView)
            }
            return
        }

        guard !query.isEmpty, documentReady else { return }
        if steppedForward {
            run(.next, in: webView)
        } else if steppedBackward {
            run(.previous, in: webView)
        }
    }

    private func run(_ step: Step, in webView: WKWebView) {
        generation += 1
        let token = generation
        let query = self.query

        switch step {
        case .next:
            find(query, backwards: false, token: token, in: webView)
        case .previous:
            find(query, backwards: true, token: token, in: webView)
        case .fresh:
            // WebKit searches on from the end of the current selection, which
            // after the previous keystroke is the match itself. Pull the caret
            // back to its start first so "fo" → "foo" stays where it is.
            webView.evaluateJavaScript(ReaderFind.anchorSelectionJS) { [weak self, weak webView] _, _ in
                guard let self, let webView, token == self.generation else { return }
                self.find(query, backwards: false, token: token, in: webView)
            }
        }
    }

    private func find(_ query: String, backwards: Bool, token: Int, in webView: WKWebView) {
        let configuration = WKFindConfiguration()
        configuration.caseSensitive = false
        configuration.wraps = true
        configuration.backwards = backwards
        webView.find(query, configuration: configuration) { [weak self, weak webView] result in
            guard let self, let webView, token == self.generation else { return }
            self.didFind(matchFound: result.matchFound, query: query, token: token, in: webView)
        }
    }

    // MARK: - Reporting

    private func didFind(matchFound: Bool, query: String, token: Int, in webView: WKWebView) {
        guard matchFound else {
            onResult?(query, ReaderFind.webStatus(matchFound: false, counted: nil))
            return
        }
        if let matchCount {
            // A step through a query already counted on this document.
            onResult?(query, ReaderFind.webStatus(matchFound: true, counted: matchCount))
            return
        }
        if let foldedPageText {
            report(query, countedIn: foldedPageText)
            return
        }
        webView.evaluateJavaScript(ReaderFind.pageTextJS) { [weak self] result, _ in
            guard let self, token == self.generation else { return }
            guard let text = result as? String else {
                // No text to count in; the match on screen is still real.
                self.onResult?(query, ReaderFind.webStatus(matchFound: true, counted: nil))
                return
            }
            let folded = ReaderFind.searchFolded(text)
            self.foldedPageText = folded
            self.report(query, countedIn: folded)
        }
    }

    private func report(_ query: String, countedIn foldedText: String) {
        let count = ReaderFind.occurrenceCount(of: query, inFolded: foldedText)
        matchCount = count
        onResult?(query, ReaderFind.webStatus(matchFound: true, counted: count))
    }

    /// Drops the selection find left behind — but only if it is still find's.
    /// A passage the reader selected by hand while the bar was open stays.
    private func clearMatchSelection(for previousQuery: String, in webView: WKWebView) {
        webView.evaluateJavaScript(ReaderFind.selectionTextJS) { [weak webView] result, _ in
            guard ReaderFind.isFindSelection(result as? String, query: previousQuery) else { return }
            webView?.evaluateJavaScript(ReaderFind.clearSelectionJS, completionHandler: nil)
        }
    }
}
#endif
