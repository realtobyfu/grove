import SwiftUI
import WebKit
import AppKit

// MARK: - Article Web View
// NSViewRepresentable wrapping WKWebView for in-app article reading.
// Intercepts link taps to open them in the browser rather than navigating away.
// Reports text selection changes to the parent via onTextSelected callback.

struct ArticleWebView: NSViewRepresentable {
    let url: URL
    var onTextSelected: ((String?) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextSelected: onTextSelected)
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

        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsLinkPreview = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTextSelected = onTextSelected
        // Reload only when the URL changes
        if webView.url?.absoluteString != url.absoluteString, !webView.isLoading {
            webView.load(URLRequest(url: url))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onTextSelected: ((String?) -> Void)?

        init(onTextSelected: ((String?) -> Void)?) {
            self.onTextSelected = onTextSelected
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

        // Handle selection change messages from injected JS
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "selectionChanged" else { return }
            if let text = message.body as? String, !text.isEmpty {
                onTextSelected?(text)
            } else {
                onTextSelected?(nil)
            }
        }
    }
}
