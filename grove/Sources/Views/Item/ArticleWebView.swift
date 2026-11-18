#if os(macOS)
import SwiftUI
import WebKit
import AppKit

// MARK: - Article Web View
// NSViewRepresentable wrapping WKWebView for in-app article reading.
// Intercepts link taps to open them in the browser rather than navigating away.
// Reports text selection changes to the parent via onTextSelected callback.
// Find-in-article runs on WebKit's own find (see ReaderWebFindDriver), which
// selects and reveals a match without touching the page's DOM.

struct ArticleWebView: NSViewRepresentable {
    let url: URL
    var onTextSelected: ((String?) -> Void)?
    /// Geometry of the reported selection, for anchoring the highlight bar.
    var onSelectionGeometry: ((WebSelectionGeometry?) -> Void)?
    /// Find-in-article: the query to show ("" for none) and the tokens that
    /// step to the next / previous match. Results come back as
    /// `(query, status)`.
    var findQuery: String = ""
    var findForwardToken: Int = 0
    var findBackwardToken: Int = 0
    var onFindResult: ((String, ReaderFind.Status) -> Void)?
    var zoomLevel: CGFloat = 1.0
    var goBackToken: Int = 0
    var goForwardToken: Int = 0
    /// In-pane navigation request (e.g. a link tapped in Reader mode):
    /// bump the token to load `navigateURL` in place.
    var navigateURL: URL? = nil
    var navigateToken: Int = 0
    var onNavigationChanged: ((Bool, Bool, URL?) -> Void)?
    /// Fires when a page finishes loading — used to run Readability extraction.
    var onPageFinished: ((WKWebView) -> Void)?
    /// Scroll-to-text request (see ReaderTemplate.scrollToTextJS).
    var scrollToTextQuery: String = ""
    var scrollToTextToken: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTextSelected: onTextSelected,
            onSelectionGeometry: onSelectionGeometry,
            onNavigationChanged: onNavigationChanged
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // Selection reporting is the shared script — same debounce, same
        // {text, rect, viewport} contract as Reader mode, so the anchored
        // action bar behaves identically in both.
        let script = WKUserScript(
            source: ReaderTemplate.selectionReporterJS(handler: "selectionChanged"),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(script)
        userContentController.add(context.coordinator, name: "selectionChanged")

        // Inject scroll-to-text helper (shared with Reader mode)
        let scrollToTextScript = WKUserScript(source: ReaderTemplate.scrollToTextJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userContentController.addUserScript(scrollToTextScript)

        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsLinkPreview = false
        context.coordinator.startObserving(webView)
        context.coordinator.lastLoadedURL = url
        // A pending in-pane navigation (link tapped in Reader mode before
        // this web view mounted) takes precedence over the item's own page.
        if let navigateURL, navigateToken != 0 {
            context.coordinator.lastNavigateToken = navigateToken
            webView.load(URLRequest(url: navigateURL))
        } else {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTextSelected = onTextSelected
        context.coordinator.onSelectionGeometry = onSelectionGeometry
        context.coordinator.findDriver.onResult = onFindResult
        context.coordinator.onNavigationChanged = onNavigationChanged
        context.coordinator.onPageFinished = onPageFinished

        // Handle scroll-to-text requests. If the page is still loading (e.g. a
        // highlight tap that just opened this panel), defer to didFinish rather
        // than firing against a page where the helper isn't injected yet.
        if scrollToTextToken != context.coordinator.lastScrollToTextToken {
            context.coordinator.lastScrollToTextToken = scrollToTextToken
            let query = scrollToTextQuery.isEmpty ? nil : scrollToTextQuery
            context.coordinator.pendingScrollQuery = query
            if let query, !webView.isLoading {
                context.coordinator.pendingScrollQuery = nil
                let escaped = ReaderTemplate.escapeForJSString(query)
                webView.evaluateJavaScript("window.__groveScrollToText('\(escaped)');", completionHandler: nil)
            }
        }

        // Apply zoom level
        webView.pageZoom = zoomLevel

        // Handle in-pane navigation requests
        if navigateToken != context.coordinator.lastNavigateToken {
            context.coordinator.lastNavigateToken = navigateToken
            if let navigateURL {
                webView.load(URLRequest(url: navigateURL))
                return
            }
        }

        // Handle back/forward navigation tokens. When the web history is
        // empty (e.g. this pane mounted directly on a link target after a
        // Reader-mode click), Back falls through to the article's own page.
        if goBackToken != context.coordinator.lastGoBackToken {
            context.coordinator.lastGoBackToken = goBackToken
            if webView.canGoBack {
                webView.goBack()
            } else {
                // No engine history: the pane mounted directly on a link
                // target, or the destination (an image document, notably)
                // recorded no entry. Back means the item's own page —
                // unconditionally, so a stale URL report can't strand the
                // user with a button that does nothing.
                webView.load(URLRequest(url: url))
            }
            return
        }
        if goForwardToken != context.coordinator.lastGoForwardToken {
            context.coordinator.lastGoForwardToken = goForwardToken
            webView.goForward()
            return
        }

        // Reload only when the article URL prop itself changes (not when WebView navigates internally)
        if url != context.coordinator.lastLoadedURL {
            context.coordinator.lastLoadedURL = url
            webView.load(URLRequest(url: url))
            // A query that is still up runs against the new page when it
            // finishes loading (see `didFinish`).
            return
        }

        // Find-in-article. The driver remembers what it was last asked, so a
        // pass that returned early above is simply caught up on the next one.
        context.coordinator.findDriver.update(
            in: webView,
            query: findQuery,
            forwardToken: findForwardToken,
            backwardToken: findBackwardToken
        )
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var onTextSelected: ((String?) -> Void)?
        var onSelectionGeometry: ((WebSelectionGeometry?) -> Void)?
        var onNavigationChanged: ((Bool, Bool, URL?) -> Void)?
        var onPageFinished: ((WKWebView) -> Void)?
        /// Find-in-article, on WebKit's own find.
        let findDriver = ReaderWebFindDriver()
        var lastGoBackToken = 0
        var lastGoForwardToken = 0
        var lastNavigateToken = 0
        var lastScrollToTextToken = 0
        var pendingScrollQuery: String? = nil
        var lastLoadedURL: URL? = nil
        private var observations: [NSKeyValueObservation] = []

        init(
            onTextSelected: ((String?) -> Void)?,
            onSelectionGeometry: ((WebSelectionGeometry?) -> Void)?,
            onNavigationChanged: ((Bool, Bool, URL?) -> Void)?
        ) {
            self.onTextSelected = onTextSelected
            self.onSelectionGeometry = onSelectionGeometry
            self.onNavigationChanged = onNavigationChanged
        }

        func startObserving(_ webView: WKWebView) {
            // WKWebView KVO fires on the main thread, but the observe handler
            // is @Sendable — assume isolation rather than hopping actors.
            observations = [
                webView.observe(\.canGoBack) { [weak self] wv, _ in
                    MainActor.assumeIsolated {
                        self?.onNavigationChanged?(wv.canGoBack, wv.canGoForward, wv.url)
                    }
                },
                webView.observe(\.canGoForward) { [weak self] wv, _ in
                    MainActor.assumeIsolated {
                        self?.onNavigationChanged?(wv.canGoBack, wv.canGoForward, wv.url)
                    }
                },
                webView.observe(\.url) { [weak self] wv, _ in
                    MainActor.assumeIsolated {
                        self?.onNavigationChanged?(wv.canGoBack, wv.canGoForward, wv.url)
                    }
                }
            ]
        }

        // Allow link clicks to navigate within the WebView. Links that
        // target a new window/tab have no target frame — load them in
        // place instead of dropping them.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // window.open / target="_blank": keep the page in this pane rather
        // than silently discarding the navigation.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let targetURL = navigationAction.request.url {
                webView.load(URLRequest(url: targetURL))
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onPageFinished?(webView)
            if let query = pendingScrollQuery {
                pendingScrollQuery = nil
                let escaped = ReaderTemplate.escapeForJSString(query)
                webView.evaluateJavaScript("window.__groveScrollToText('\(escaped)');", completionHandler: nil)
            }
            // The page under an open find bar changed: search the new one.
            findDriver.documentDidFinish(in: webView)
        }

        // Handle messages from injected JS
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "selectionChanged" {
                let selection = WebSelectionGeometry.decode(message.body)
                onTextSelected?(selection.text)
                onSelectionGeometry?(selection.geometry)
            }
        }
    }
}
#endif
