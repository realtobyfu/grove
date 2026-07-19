import SwiftUI

#if os(iOS)
import WebKit

/// UIViewRepresentable wrapping WKWebView for in-app article reading.
/// Handles link interception (opens external browser), text selection tracking,
/// and find-in-page via JavaScript highlighting.
struct MobileArticleWebView: UIViewRepresentable {
    let url: URL
    var onTextSelected: ((String?) -> Void)?
    var findQuery: String = ""
    var findForwardToken: Int = 0
    var findBackwardToken: Int = 0
    var onFindResult: ((Int, Int) -> Void)?
    var zoomLevel: CGFloat = 1.0
    /// Scroll-to-text request (see ReaderTemplate.scrollToTextJS).
    var scrollToTextQuery: String = ""
    var scrollToTextToken: Int = 0
    @Environment(\.openURL) private var openURL

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextSelected: onTextSelected, openURL: openURL)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // Inject text selection tracking script
        let selectionScript = WKUserScript(
            source: Self.selectionJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(selectionScript)
        config.userContentController.add(context.coordinator, name: "textSelected")

        // Inject scroll-to-text helper (shared with Reader mode)
        let scrollToTextScript = WKUserScript(
            source: ReaderTemplate.scrollToTextJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(scrollToTextScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground

        // Enable reader mode via content rules (strip ads) if possible
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTextSelected = onTextSelected

        // Handle scroll-to-text requests. Defer to didFinish while the page is
        // still loading (e.g. a highlight tap that just opened the panel) so the
        // request isn't fired before the helper script exists.
        if scrollToTextToken != coordinator.lastScrollToTextToken {
            coordinator.lastScrollToTextToken = scrollToTextToken
            let query = scrollToTextQuery.isEmpty ? nil : scrollToTextQuery
            coordinator.pendingScrollQuery = query
            if let query, !webView.isLoading {
                coordinator.pendingScrollQuery = nil
                let escaped = ReaderTemplate.escapeForJSString(query)
                webView.evaluateJavaScript("window.__groveScrollToText('\(escaped)');", completionHandler: nil)
            }
        }

        if webView.url?.absoluteString != url.absoluteString, !webView.isLoading {
            webView.load(URLRequest(url: url))
            coordinator.lastFindQuery = ""
            coordinator.lastForwardToken = 0
            coordinator.lastBackwardToken = 0
            coordinator.lastZoomLevel = 0
            onFindResult?(0, 0)
            return
        }

        // Apply zoom level via CSS zoom
        if zoomLevel != coordinator.lastZoomLevel {
            coordinator.lastZoomLevel = zoomLevel
            let pct = Int(round(zoomLevel * 100))
            webView.evaluateJavaScript("document.body.style.zoom = '\(pct)%';", completionHandler: nil)
        }

        // Handle find-in-page updates
        if findQuery != coordinator.lastFindQuery {
            coordinator.lastFindQuery = findQuery
            if findQuery.isEmpty {
                webView.evaluateJavaScript(Self.clearFindJS, completionHandler: nil)
                onFindResult?(0, 0)
            } else {
                let escapedQuery = findQuery.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                let js = "window.__groveFindAll('\(escapedQuery)');"
                webView.evaluateJavaScript(js) { result, _ in
                    if let count = result as? Int {
                        onFindResult?(count > 0 ? 1 : 0, count)
                    }
                }
            }
            coordinator.lastForwardToken = findForwardToken
            coordinator.lastBackwardToken = findBackwardToken
        } else {
            if findForwardToken != coordinator.lastForwardToken {
                coordinator.lastForwardToken = findForwardToken
                webView.evaluateJavaScript("window.__groveFindNext();") { result, _ in
                    if let arr = result as? [Int], arr.count == 2 {
                        onFindResult?(arr[0], arr[1])
                    }
                }
            }
            if findBackwardToken != coordinator.lastBackwardToken {
                coordinator.lastBackwardToken = findBackwardToken
                webView.evaluateJavaScript("window.__groveFindPrev();") { result, _ in
                    if let arr = result as? [Int], arr.count == 2 {
                        onFindResult?(arr[0], arr[1])
                    }
                }
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onTextSelected: ((String?) -> Void)?
        let openURL: OpenURLAction
        var lastFindQuery = ""
        var lastForwardToken = 0
        var lastBackwardToken = 0
        var lastScrollToTextToken = 0
        var pendingScrollQuery: String? = nil
        var lastZoomLevel: CGFloat = 1.0

        init(onTextSelected: ((String?) -> Void)?, openURL: OpenURLAction) {
            self.onTextSelected = onTextSelected
            self.openURL = openURL
        }

        // Intercept links — open externally instead of navigating in-app
        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated,
                  let linkURL = navigationAction.request.url else {
                return .allow
            }
            openURL(linkURL)
            return .cancel
        }

        @MainActor
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let query = pendingScrollQuery {
                pendingScrollQuery = nil
                let escaped = ReaderTemplate.escapeForJSString(query)
                webView.evaluateJavaScript("window.__groveScrollToText('\(escaped)');", completionHandler: nil)
            }
        }

        // Receive text selection from JavaScript
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "textSelected" {
                let text = message.body as? String
                onTextSelected?(text?.isEmpty == true ? nil : text)
            }
        }
    }

    // MARK: - JavaScript

    private static let selectionJS = """
    (function() {
        function reportSelection() {
            var sel = window.getSelection();
            var text = sel ? sel.toString() : '';
            window.webkit.messageHandlers.textSelected.postMessage(text);
        }
        document.addEventListener('selectionchange', reportSelection);
    })();

    // Find-in-page support
    window.__groveMatches = [];
    window.__groveMatchIndex = -1;

    window.__groveClearFind = function() {
        document.querySelectorAll('mark.grove-find').forEach(function(m) {
            m.outerHTML = m.textContent;
        });
        window.__groveMatches = [];
        window.__groveMatchIndex = -1;
    };

    window.__groveFindAll = function(query) {
        window.__groveClearFind();
        if (!query) return 0;
        var body = document.body;
        var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null, false);
        var ranges = [];
        var node;
        var lowerQuery = query.toLowerCase();
        while (node = walker.nextNode()) {
            var text = node.textContent.toLowerCase();
            var idx = 0;
            while ((idx = text.indexOf(lowerQuery, idx)) !== -1) {
                var range = document.createRange();
                range.setStart(node, idx);
                range.setEnd(node, idx + query.length);
                ranges.push(range);
                idx += query.length;
            }
        }
        ranges.forEach(function(range, i) {
            var mark = document.createElement('mark');
            mark.className = 'grove-find';
            mark.style.backgroundColor = 'yellow';
            mark.style.color = 'black';
            range.surroundContents(mark);
        });
        window.__groveMatches = document.querySelectorAll('mark.grove-find');
        if (window.__groveMatches.length > 0) {
            window.__groveMatchIndex = 0;
            window.__groveMatches[0].style.backgroundColor = 'orange';
            window.__groveMatches[0].scrollIntoView({behavior:'smooth',block:'center'});
        }
        return window.__groveMatches.length;
    };

    window.__groveFindNext = function() {
        if (window.__groveMatches.length === 0) return [0, 0];
        window.__groveMatches[window.__groveMatchIndex].style.backgroundColor = 'yellow';
        window.__groveMatchIndex = (window.__groveMatchIndex + 1) % window.__groveMatches.length;
        window.__groveMatches[window.__groveMatchIndex].style.backgroundColor = 'orange';
        window.__groveMatches[window.__groveMatchIndex].scrollIntoView({behavior:'smooth',block:'center'});
        return [window.__groveMatchIndex + 1, window.__groveMatches.length];
    };

    window.__groveFindPrev = function() {
        if (window.__groveMatches.length === 0) return [0, 0];
        window.__groveMatches[window.__groveMatchIndex].style.backgroundColor = 'yellow';
        window.__groveMatchIndex = (window.__groveMatchIndex - 1 + window.__groveMatches.length) % window.__groveMatches.length;
        window.__groveMatches[window.__groveMatchIndex].style.backgroundColor = 'orange';
        window.__groveMatches[window.__groveMatchIndex].scrollIntoView({behavior:'smooth',block:'center'});
        return [window.__groveMatchIndex + 1, window.__groveMatches.length];
    };
    """

    private static let clearFindJS = "window.__groveClearFind();"
}
#endif
