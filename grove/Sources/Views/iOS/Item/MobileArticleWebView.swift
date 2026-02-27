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

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
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
        // Handle find-in-page updates
        let coordinator = context.coordinator

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
        let parent: MobileArticleWebView
        var lastFindQuery = ""
        var lastForwardToken = 0
        var lastBackwardToken = 0

        init(parent: MobileArticleWebView) {
            self.parent = parent
        }

        // Intercept links — open externally instead of navigating in-app
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated,
                  let linkURL = navigationAction.request.url else {
                return .allow
            }
            await UIApplication.shared.open(linkURL)
            return .cancel
        }

        // Receive text selection from JavaScript
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "textSelected" {
                let text = message.body as? String
                parent.onTextSelected?(text?.isEmpty == true ? nil : text)
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
