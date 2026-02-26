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

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextSelected: onTextSelected, onFindResult: onFindResult)
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

        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsLinkPreview = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTextSelected = onTextSelected
        context.coordinator.onFindResult = onFindResult

        // Reload only when the URL changes
        if webView.url?.absoluteString != url.absoluteString, !webView.isLoading {
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
        var lastFindQuery = ""
        var lastForwardToken = 0
        var lastBackwardToken = 0

        init(onTextSelected: ((String?) -> Void)?, onFindResult: ((Int, Int) -> Void)?) {
            self.onTextSelected = onTextSelected
            self.onFindResult = onFindResult
        }

        // Intercept link clicks — open in default browser, stay on original page
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
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
