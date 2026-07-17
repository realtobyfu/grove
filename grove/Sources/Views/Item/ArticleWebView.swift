#if os(macOS)
import SwiftUI
import WebKit
import AppKit

// MARK: - Article Web View
// NSViewRepresentable wrapping WKWebView for in-app article reading.
// Intercepts link taps to open them in the browser rather than navigating away.
// Reports text selection changes to the parent via onTextSelected callback.
// Supports find-in-page via JavaScript highlight/scroll approach.

struct ArticleWebView: NSViewRepresentable {
    let url: URL
    var onTextSelected: ((String?) -> Void)?
    var findQuery: String = ""
    var findForwardToken: Int = 0
    var findBackwardToken: Int = 0
    var onFindResult: ((Int, Int) -> Void)?
    var zoomLevel: CGFloat = 1.0
    var goBackToken: Int = 0
    var goForwardToken: Int = 0
    var onNavigationChanged: ((Bool, Bool, URL?) -> Void)?
    /// Fires when a page finishes loading — used to run Readability extraction.
    var onPageFinished: ((WKWebView) -> Void)?
    /// Scroll-to-text request (see ReaderTemplate.scrollToTextJS).
    var scrollToTextQuery: String = ""
    var scrollToTextToken: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextSelected: onTextSelected, onFindResult: onFindResult, onNavigationChanged: onNavigationChanged)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // Inject selection-change listener
        let script = WKUserScript(source: """
            (function() {
                var debounceTimer = null;
                function reportSelection() {
                    var sel = window.getSelection();
                    var text = sel ? sel.toString().trim() : "";
                    window.webkit.messageHandlers.selectionChanged.postMessage(text);
                }
                function debouncedReport() {
                    clearTimeout(debounceTimer);
                    debounceTimer = setTimeout(reportSelection, 150);
                }
                document.addEventListener('mouseup', debouncedReport);
                document.addEventListener('keyup', debouncedReport);
                document.addEventListener('selectionchange', debouncedReport);
            })();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userContentController.addUserScript(script)
        userContentController.add(context.coordinator, name: "selectionChanged")

        // Inject find-in-page helper
        let findScript = WKUserScript(source: Self.findHelperJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userContentController.addUserScript(findScript)
        userContentController.add(context.coordinator, name: "findResult")

        // Inject scroll-to-text helper (shared with Reader mode)
        let scrollToTextScript = WKUserScript(source: ReaderTemplate.scrollToTextJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userContentController.addUserScript(scrollToTextScript)

        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsLinkPreview = false
        context.coordinator.startObserving(webView)
        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTextSelected = onTextSelected
        context.coordinator.onFindResult = onFindResult
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

        // Handle back/forward navigation tokens
        if goBackToken != context.coordinator.lastGoBackToken {
            context.coordinator.lastGoBackToken = goBackToken
            webView.goBack()
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
            context.coordinator.lastFindQuery = ""
            context.coordinator.lastForwardToken = 0
            context.coordinator.lastBackwardToken = 0
            return
        }

        let queryChanged = findQuery != context.coordinator.lastFindQuery
        let forwardChanged = findForwardToken != context.coordinator.lastForwardToken
        let backwardChanged = findBackwardToken != context.coordinator.lastBackwardToken

        context.coordinator.lastFindQuery = findQuery
        context.coordinator.lastForwardToken = findForwardToken
        context.coordinator.lastBackwardToken = findBackwardToken

        if queryChanged {
            if findQuery.isEmpty {
                webView.evaluateJavaScript("window.__groveFindClear();", completionHandler: nil)
                onFindResult?(0, 0)
            } else {
                let escaped = findQuery.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                    .replacingOccurrences(of: "\n", with: "\\n")
                webView.evaluateJavaScript("window.__groveFind('\(escaped)');", completionHandler: nil)
            }
        } else if forwardChanged && !findQuery.isEmpty {
            webView.evaluateJavaScript("window.__groveFindNext();", completionHandler: nil)
        } else if backwardChanged && !findQuery.isEmpty {
            webView.evaluateJavaScript("window.__groveFindPrev();", completionHandler: nil)
        }
    }

    // MARK: - Find Helper JavaScript

    private static let findHelperJS: String = """
    (function() {
        var matches = [];
        var currentIndex = -1;
        var highlightStyle = 'background: #FFEB3B; color: #000;';
        var activeStyle = 'background: #F57C00; color: #fff;';

        function clearHighlights() {
            var marks = document.querySelectorAll('mark[data-grove-find]');
            marks.forEach(function(mark) {
                var parent = mark.parentNode;
                parent.replaceChild(document.createTextNode(mark.textContent), mark);
                parent.normalize();
            });
            matches = [];
            currentIndex = -1;
        }

        function highlightMatches(query) {
            clearHighlights();
            if (!query) { reportResult(); return; }
            var lower = query.toLowerCase();
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
            var textNodes = [];
            while (walker.nextNode()) {
                var node = walker.currentNode;
                if (node.parentElement && (node.parentElement.tagName === 'SCRIPT' ||
                    node.parentElement.tagName === 'STYLE' || node.parentElement.tagName === 'NOSCRIPT')) continue;
                if (node.textContent.toLowerCase().indexOf(lower) !== -1) {
                    textNodes.push(node);
                }
            }
            textNodes.forEach(function(node) {
                var text = node.textContent;
                var lowerText = text.toLowerCase();
                var idx = 0;
                var parts = [];
                while (true) {
                    var found = lowerText.indexOf(lower, idx);
                    if (found === -1) break;
                    if (found > idx) parts.push(document.createTextNode(text.substring(idx, found)));
                    var mark = document.createElement('mark');
                    mark.setAttribute('data-grove-find', 'true');
                    mark.setAttribute('style', highlightStyle);
                    mark.textContent = text.substring(found, found + query.length);
                    parts.push(mark);
                    matches.push(mark);
                    idx = found + query.length;
                }
                if (parts.length > 0) {
                    if (idx < text.length) parts.push(document.createTextNode(text.substring(idx)));
                    var parent = node.parentNode;
                    parts.forEach(function(p) { parent.insertBefore(p, node); });
                    parent.removeChild(node);
                }
            });
            if (matches.length > 0) {
                currentIndex = 0;
                activateCurrent();
            }
            reportResult();
        }

        function activateCurrent() {
            matches.forEach(function(m, i) {
                m.setAttribute('style', i === currentIndex ? activeStyle : highlightStyle);
            });
            if (currentIndex >= 0 && currentIndex < matches.length) {
                matches[currentIndex].scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        }

        function findNext() {
            if (matches.length === 0) return;
            currentIndex = (currentIndex + 1) % matches.length;
            activateCurrent();
            reportResult();
        }

        function findPrev() {
            if (matches.length === 0) return;
            currentIndex = (currentIndex - 1 + matches.length) % matches.length;
            activateCurrent();
            reportResult();
        }

        function reportResult() {
            var current = matches.length > 0 ? currentIndex + 1 : 0;
            var total = matches.length;
            window.webkit.messageHandlers.findResult.postMessage({ current: current, total: total });
        }

        window.__groveFind = highlightMatches;
        window.__groveFindNext = findNext;
        window.__groveFindPrev = findPrev;
        window.__groveFindClear = function() { clearHighlights(); reportResult(); };
    })();
    """

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onTextSelected: ((String?) -> Void)?
        var onFindResult: ((Int, Int) -> Void)?
        var onNavigationChanged: ((Bool, Bool, URL?) -> Void)?
        var onPageFinished: ((WKWebView) -> Void)?
        var lastFindQuery = ""
        var lastForwardToken = 0
        var lastBackwardToken = 0
        var lastGoBackToken = 0
        var lastGoForwardToken = 0
        var lastScrollToTextToken = 0
        var pendingScrollQuery: String? = nil
        var lastLoadedURL: URL? = nil
        private var observations: [NSKeyValueObservation] = []

        init(onTextSelected: ((String?) -> Void)?, onFindResult: ((Int, Int) -> Void)?, onNavigationChanged: ((Bool, Bool, URL?) -> Void)?) {
            self.onTextSelected = onTextSelected
            self.onFindResult = onFindResult
            self.onNavigationChanged = onNavigationChanged
        }

        func startObserving(_ webView: WKWebView) {
            observations = [
                webView.observe(\.canGoBack) { [weak self] wv, _ in
                    self?.onNavigationChanged?(wv.canGoBack, wv.canGoForward, wv.url)
                },
                webView.observe(\.canGoForward) { [weak self] wv, _ in
                    self?.onNavigationChanged?(wv.canGoBack, wv.canGoForward, wv.url)
                },
                webView.observe(\.url) { [weak self] wv, _ in
                    self?.onNavigationChanged?(wv.canGoBack, wv.canGoForward, wv.url)
                }
            ]
        }

        // Allow link clicks to navigate within the WebView
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onPageFinished?(webView)
            if let query = pendingScrollQuery {
                pendingScrollQuery = nil
                let escaped = ReaderTemplate.escapeForJSString(query)
                webView.evaluateJavaScript("window.__groveScrollToText('\(escaped)');", completionHandler: nil)
            }
        }

        // Handle messages from injected JS
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "selectionChanged" {
                if let text = message.body as? String, !text.isEmpty {
                    onTextSelected?(text)
                } else {
                    onTextSelected?(nil)
                }
            } else if message.name == "findResult" {
                if let dict = message.body as? [String: Any],
                   let current = dict["current"] as? Int,
                   let total = dict["total"] as? Int {
                    onFindResult?(current, total)
                }
            }
        }
    }
}
#endif
