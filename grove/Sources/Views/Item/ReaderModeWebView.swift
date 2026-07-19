import SwiftUI
import WebKit

// MARK: - Reader Typography Settings

/// User-adjustable typography for Reader mode. Persisted via @AppStorage keys
/// in ItemReaderWebViewPanel; applied live through CSS variables (no reload).
struct ReaderTypographySettings: Equatable {
    /// Font size step 0...3.
    var sizeStep: Int = 1
    /// Narrow (~66ch) or wide (~80ch) measure.
    var isWide: Bool = false
    /// Serif (Newsreader) or sans (IBM Plex Sans) body.
    var useSerif: Bool = true

    static let sizeStepRange = 0...3
    static let sizeStepKey = "reader.typography.sizeStep"
    static let isWideKey = "reader.typography.isWide"
    static let useSerifKey = "reader.typography.useSerif"

    var fontSizePx: Int {
        let sizes = [16, 18, 20, 23]
        return sizes[min(max(sizeStep, 0), sizes.count - 1)]
    }

    var measureCh: Int { isWide ? 80 : 66 }

    var bodyFontStack: String {
        useSerif ? ReaderTemplate.serifStack : ReaderTemplate.sansStack
    }
}

// MARK: - Reader Template

/// Builds the self-contained HTML page for Reader mode and holds the
/// JavaScript shared with the live-page web views (scroll-to-text).
enum ReaderTemplate {
    static let serifStack = "'Newsreader', 'Iowan Old Style', Georgia, 'Times New Roman', serif"
    static let sansStack = "'IBM Plex Sans', -apple-system, 'Helvetica Neue', sans-serif"
    static let monoStack = "'IBM Plex Mono', ui-monospace, 'SF Mono', Menlo, monospace"

    // MARK: Fonts

    /// @font-face rules embedding the bundled Grove fonts as base64 data URIs
    /// (a strict-CSP-free, file-access-free way to use them inside
    /// loadHTMLString content). Falls back to empty CSS when a font file
    /// cannot be located — the CSS stacks then resolve to system fonts.
    private static let embeddedFontCSS: String = {
        let faces: [(family: String, file: String, weight: Int, style: String)] = [
            ("Newsreader", "Newsreader-Regular", 400, "normal"),
            ("Newsreader", "Newsreader-Italic", 400, "italic"),
            ("Newsreader", "Newsreader-Medium", 500, "normal"),
            ("IBM Plex Sans", "IBMPlexSans-Regular", 400, "normal"),
            ("IBM Plex Sans", "IBMPlexSans-Medium", 500, "normal"),
            ("IBM Plex Mono", "IBMPlexMono-Regular", 400, "normal"),
        ]
        return faces.compactMap { face in
            let url = Bundle.main.url(forResource: face.file, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: face.file, withExtension: "ttf")
            guard let url, let data = try? Data(contentsOf: url) else { return nil }
            return """
            @font-face {
                font-family: '\(face.family)';
                src: url(data:font/ttf;base64,\(data.base64EncodedString())) format('truetype');
                font-weight: \(face.weight);
                font-style: \(face.style);
                font-display: swap;
            }
            """
        }.joined(separator: "\n")
    }()

    // MARK: Shared JavaScript

    /// Scroll-to-text helper shared by Reader mode and live pages.
    /// `window.__groveScrollToText(query)` finds the first case-insensitive
    /// occurrence of `query` in the page text, smooth-scrolls it into view,
    /// and flashes a monochrome overlay marker. Returns true when found.
    static let scrollToTextJS = """
    window.__groveScrollToText = function(query) {
        if (!query) { return false; }
        // Concatenate all visible text nodes so a match can span inline markup
        // (links, <em>/<strong>/<code>) instead of only matching within a
        // single text node.
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
        var nodes = [];
        var full = '';
        while (walker.nextNode()) {
            var node = walker.currentNode;
            var p = node.parentElement;
            if (p && (p.tagName === 'SCRIPT' || p.tagName === 'STYLE' || p.tagName === 'NOSCRIPT')) { continue; }
            nodes.push({ node: node, start: full.length });
            full += node.textContent;
        }
        if (nodes.length === 0) { return false; }
        var idx = full.toLowerCase().indexOf(query.toLowerCase());
        if (idx === -1) { return false; }
        var endIdx = idx + query.length;
        function locate(offset) {
            for (var i = 0; i < nodes.length; i++) {
                var n = nodes[i];
                var len = n.node.textContent.length;
                if (offset <= n.start + len) {
                    return { node: n.node, offset: Math.max(0, Math.min(offset - n.start, len)) };
                }
            }
            var last = nodes[nodes.length - 1];
            return { node: last.node, offset: last.node.textContent.length };
        }
        var startLoc = locate(idx);
        var endLoc = locate(endIdx);
        var range = document.createRange();
        try {
            range.setStart(startLoc.node, startLoc.offset);
            range.setEnd(endLoc.node, endLoc.offset);
        } catch (e) { return false; }
        var rect = range.getBoundingClientRect();
        window.scrollTo({ top: window.scrollY + rect.top - window.innerHeight * 0.3, behavior: 'smooth' });
        var mark = document.createElement('div');
        mark.style.cssText = 'position:absolute;pointer-events:none;background:rgba(128,128,128,0.35);border-radius:2px;transition:opacity 0.6s ease 0.9s;opacity:1;z-index:2147483647;';
        mark.style.left = (window.scrollX + rect.left - 2) + 'px';
        mark.style.top = (window.scrollY + rect.top - 1) + 'px';
        mark.style.width = (rect.width + 4) + 'px';
        mark.style.height = (rect.height + 2) + 'px';
        document.body.appendChild(mark);
        requestAnimationFrame(function() { mark.style.opacity = '0'; });
        setTimeout(function() { mark.remove(); }, 1800);
        return true;
    };
    """

    /// Debounced selection reporter — same message contract as the live-page
    /// web views: posts the selected string (or "") to `selectionChanged`.
    static let selectionReporterJS = """
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
    """

    /// Throttled scroll listener posting a 0–1 reading fraction to
    /// `readingProgress`.
    static let progressReporterJS = """
    (function() {
        var lastSent = -1;
        var timer = null;
        function send() {
            var doc = document.documentElement;
            var max = doc.scrollHeight - window.innerHeight;
            var f = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
            if (Math.abs(f - lastSent) >= 0.005) {
                lastSent = f;
                window.webkit.messageHandlers.readingProgress.postMessage(f);
            }
        }
        window.addEventListener('scroll', function() {
            if (timer) { return; }
            timer = setTimeout(function() { timer = null; send(); }, 250);
        }, { passive: true });
        window.addEventListener('pagehide', send);
    })();
    """

    // MARK: Page

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func escapeForJSString(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }

    /// Full reader page. Monochrome palette mirroring the app's asset colors:
    /// light bg #FAFAFA / text #1A1A1A, dark bg #111111 / text #E8E8E8.
    /// Follows prefers-color-scheme by default, with an explicit
    /// data-grove-theme override the app keeps in sync with its own scheme.
    static func page(
        article: ReadableArticle,
        typography: ReaderTypographySettings,
        isDark: Bool,
        readMinutes: Int
    ) -> String {
        let title = escapeHTML(article.title)
        let byline = article.byline.flatMap { $0.isEmpty ? nil : escapeHTML($0) }
        let host = article.sourceURLString.flatMap { URL(string: $0)?.host }.map(escapeHTML)
        let metaParts = [byline, host, "\(readMinutes) min read"].compactMap(\.self)
        let baseTag = article.sourceURLString.map { "<base href=\"\(escapeHTML($0))\">" } ?? ""

        return """
        <!DOCTYPE html>
        <html data-grove-theme="\(isDark ? "dark" : "light")">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(baseTag)
        <title>\(title)</title>
        <style>
        \(embeddedFontCSS)
        :root {
            --reader-size: \(typography.fontSizePx)px;
            --reader-measure: \(typography.measureCh)ch;
            --reader-font: \(typography.bodyFontStack);
            --bg: #FAFAFA;
            --fg: #1A1A1A;
            --fg-secondary: #666666;
            --border: #EBEBEB;
            --code-bg: #F0F0EE;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #111111;
                --fg: #E8E8E8;
                --fg-secondary: #9E9E9E;
                --border: #222222;
                --code-bg: #1C1C1C;
            }
        }
        :root[data-grove-theme="light"] {
            --bg: #FAFAFA;
            --fg: #1A1A1A;
            --fg-secondary: #666666;
            --border: #EBEBEB;
            --code-bg: #F0F0EE;
        }
        :root[data-grove-theme="dark"] {
            --bg: #111111;
            --fg: #E8E8E8;
            --fg-secondary: #9E9E9E;
            --border: #222222;
            --code-bg: #1C1C1C;
        }
        * { box-sizing: border-box; }
        html { -webkit-text-size-adjust: 100%; }
        body {
            margin: 0;
            background: var(--bg);
            color: var(--fg);
            font-family: var(--reader-font);
            font-size: var(--reader-size);
            line-height: 1.68;
            -webkit-font-smoothing: antialiased;
        }
        .grove-reader {
            max-width: var(--reader-measure);
            margin: 0 auto;
            padding: 48px 24px 96px;
        }
        .grove-title {
            font-family: \(serifStack);
            font-weight: 500;
            font-size: 1.9em;
            line-height: 1.22;
            letter-spacing: -0.012em;
            margin: 0 0 0.4em;
        }
        .grove-meta {
            font-family: \(monoStack);
            font-size: 0.72em;
            letter-spacing: 0.02em;
            color: var(--fg-secondary);
            margin: 0 0 2.2em;
        }
        .grove-meta span + span::before {
            content: "\\00a0\\00b7\\00a0\\00a0";
        }
        .grove-content > * + * { margin-top: 1em; }
        .grove-content h1, .grove-content h2, .grove-content h3,
        .grove-content h4, .grove-content h5, .grove-content h6 {
            font-family: var(--reader-font);
            font-weight: 500;
            line-height: 1.3;
            margin: 1.6em 0 0.5em;
        }
        .grove-content h1 { font-size: 1.5em; }
        .grove-content h2 { font-size: 1.3em; }
        .grove-content h3 { font-size: 1.15em; }
        .grove-content h4, .grove-content h5, .grove-content h6 { font-size: 1em; }
        .grove-content p { margin: 0 0 1em; }
        .grove-content a {
            color: inherit;
            text-decoration: underline;
            text-decoration-color: var(--fg-secondary);
            text-underline-offset: 2px;
        }
        .grove-content img, .grove-content video, .grove-content svg {
            max-width: 100%;
            height: auto;
        }
        .grove-content figure { margin: 1.6em 0; }
        .grove-content figcaption {
            font-family: \(monoStack);
            font-size: 0.72em;
            color: var(--fg-secondary);
            margin-top: 0.6em;
        }
        .grove-content blockquote {
            margin: 1.4em 0;
            padding-left: 1em;
            border-left: 2px solid var(--border);
            color: var(--fg-secondary);
            font-style: italic;
        }
        .grove-content pre, .grove-content code {
            font-family: \(monoStack);
            font-size: 0.85em;
            background: var(--code-bg);
        }
        .grove-content code { padding: 0.1em 0.35em; border-radius: 3px; }
        .grove-content pre {
            padding: 0.9em 1em;
            border-radius: 6px;
            overflow-x: auto;
            line-height: 1.5;
        }
        .grove-content pre code { padding: 0; background: transparent; }
        .grove-content hr {
            border: none;
            border-top: 1px solid var(--border);
            margin: 2.2em 0;
        }
        .grove-content table {
            border-collapse: collapse;
            width: 100%;
            font-size: 0.9em;
            display: block;
            overflow-x: auto;
        }
        .grove-content th, .grove-content td {
            border: 1px solid var(--border);
            padding: 0.45em 0.7em;
            text-align: left;
        }
        .grove-content ul, .grove-content ol { padding-left: 1.4em; }
        .grove-content li { margin: 0.25em 0; }
        ::selection { background: rgba(128, 128, 128, 0.3); }
        </style>
        </head>
        <body>
        <article class="grove-reader">
        <h1 class="grove-title">\(title)</h1>
        <p class="grove-meta">\(metaParts.map { "<span>\($0)</span>" }.joined())</p>
        <div class="grove-content">
        \(article.contentHTML)
        </div>
        </article>
        </body>
        </html>
        """
    }

    /// Live typography update — sets CSS variables on :root without a reload.
    static func typographyUpdateJS(_ typography: ReaderTypographySettings) -> String {
        """
        (function() {
            var s = document.documentElement.style;
            s.setProperty('--reader-size', '\(typography.fontSizePx)px');
            s.setProperty('--reader-measure', '\(typography.measureCh)ch');
            s.setProperty('--reader-font', "\(typography.bodyFontStack)");
        })();
        """
    }

    /// Live theme update keeping the page in sync with the app's color scheme.
    static func themeUpdateJS(isDark: Bool) -> String {
        "document.documentElement.setAttribute('data-grove-theme', '\(isDark ? "dark" : "light")');"
    }

    /// Restores a previously persisted scroll fraction (0–1).
    static func restoreProgressJS(_ fraction: Double) -> String {
        """
        (function() {
            var f = \(fraction);
            function apply() {
                var doc = document.documentElement;
                var max = doc.scrollHeight - window.innerHeight;
                if (max > 0) { window.scrollTo(0, f * max); }
            }
            apply();
            // Late-loading images grow the page after didFinish; re-apply the
            // fraction for a few seconds so restore lands at the real position
            // instead of short (which would then be re-persisted too small).
            window.addEventListener('load', apply);
            var count = 0;
            var timer = setInterval(function() {
                apply();
                if (++count >= 6) { clearInterval(timer); }
            }, 500);
            // Stop fighting the user the moment they scroll intentionally.
            ['wheel', 'touchstart', 'keydown', 'mousedown'].forEach(function(ev) {
                window.addEventListener(ev, function() {
                    clearInterval(timer);
                    window.removeEventListener('load', apply);
                }, { once: true, passive: true });
            });
        })();
        """
    }
}

// MARK: - Reader Mode Web View

/// Renders an extracted ReadableArticle in Grove's own reader template.
/// Selection changes surface through onTextSelected with the same contract
/// as the live-page web views; scroll position reports through
/// onScrollProgress as a 0–1 fraction.
#if os(macOS)
struct ReaderModeWebView: NSViewRepresentable {
    let article: ReadableArticle
    var typography: ReaderTypographySettings
    var isDark: Bool
    var initialProgress: Double = 0
    var scrollToTextQuery: String = ""
    var scrollToTextToken: Int = 0
    var onTextSelected: ((String?) -> Void)?
    var onScrollProgress: ((Double) -> Void)?
    var onOpenExternalLink: ((URL) -> Void)?

    func makeCoordinator() -> ReaderModeCoordinator {
        ReaderModeCoordinator(
            onTextSelected: onTextSelected,
            onScrollProgress: onScrollProgress,
            onOpenExternalLink: onOpenExternalLink
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = ReaderModeSupport.makeWebView(coordinator: context.coordinator)
        ReaderModeSupport.load(article, typography: typography, isDark: isDark, initialProgress: initialProgress, into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        ReaderModeSupport.update(
            webView,
            coordinator: context.coordinator,
            article: article,
            typography: typography,
            isDark: isDark,
            initialProgress: initialProgress,
            scrollToTextQuery: scrollToTextQuery,
            scrollToTextToken: scrollToTextToken,
            onTextSelected: onTextSelected,
            onScrollProgress: onScrollProgress,
            onOpenExternalLink: onOpenExternalLink
        )
    }
}
#endif

#if os(iOS)
struct ReaderModeWebView: UIViewRepresentable {
    let article: ReadableArticle
    var typography: ReaderTypographySettings
    var isDark: Bool
    var initialProgress: Double = 0
    var scrollToTextQuery: String = ""
    var scrollToTextToken: Int = 0
    var onTextSelected: ((String?) -> Void)?
    var onScrollProgress: ((Double) -> Void)?
    var onOpenExternalLink: ((URL) -> Void)?

    func makeCoordinator() -> ReaderModeCoordinator {
        ReaderModeCoordinator(
            onTextSelected: onTextSelected,
            onScrollProgress: onScrollProgress,
            onOpenExternalLink: onOpenExternalLink
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = ReaderModeSupport.makeWebView(coordinator: context.coordinator)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        ReaderModeSupport.load(article, typography: typography, isDark: isDark, initialProgress: initialProgress, into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        ReaderModeSupport.update(
            webView,
            coordinator: context.coordinator,
            article: article,
            typography: typography,
            isDark: isDark,
            initialProgress: initialProgress,
            scrollToTextQuery: scrollToTextQuery,
            scrollToTextToken: scrollToTextToken,
            onTextSelected: onTextSelected,
            onScrollProgress: onScrollProgress,
            onOpenExternalLink: onOpenExternalLink
        )
    }
}
#endif

// MARK: - Shared Reader Support

/// Platform-neutral construction/update logic shared by the macOS and iOS
/// representables.
@MainActor
enum ReaderModeSupport {
    static func makeWebView(coordinator: ReaderModeCoordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        userContentController.addUserScript(WKUserScript(
            source: ReaderTemplate.selectionReporterJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        userContentController.addUserScript(WKUserScript(
            source: ReaderTemplate.progressReporterJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        userContentController.addUserScript(WKUserScript(
            source: ReaderTemplate.scrollToTextJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        userContentController.add(coordinator, name: "selectionChanged")
        userContentController.add(coordinator, name: "readingProgress")
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.allowsLinkPreview = false
        return webView
    }

    static func load(
        _ article: ReadableArticle,
        typography: ReaderTypographySettings,
        isDark: Bool,
        initialProgress: Double,
        into webView: WKWebView,
        coordinator: ReaderModeCoordinator
    ) {
        coordinator.loadedArticleKey = articleKey(article)
        coordinator.lastTypography = typography
        coordinator.lastIsDark = isDark
        coordinator.pendingRestoreProgress = (initialProgress > 0.01 && initialProgress < 0.99) ? initialProgress : nil
        let html = ReaderTemplate.page(
            article: article,
            typography: typography,
            isDark: isDark,
            readMinutes: article.readMinutes
        )
        // Base URL comes from the <base> tag in the template, so relative
        // image paths in article HTML resolve against the original site
        // and remote images may load live.
        webView.loadHTMLString(html, baseURL: article.sourceURLString.flatMap(URL.init(string:)))
    }

    static func update(
        _ webView: WKWebView,
        coordinator: ReaderModeCoordinator,
        article: ReadableArticle,
        typography: ReaderTypographySettings,
        isDark: Bool,
        initialProgress: Double,
        scrollToTextQuery: String,
        scrollToTextToken: Int,
        onTextSelected: ((String?) -> Void)?,
        onScrollProgress: ((Double) -> Void)?,
        onOpenExternalLink: ((URL) -> Void)?
    ) {
        coordinator.onTextSelected = onTextSelected
        coordinator.onScrollProgress = onScrollProgress
        coordinator.onOpenExternalLink = onOpenExternalLink

        // Capture a scroll-to-text request before any early return so it can be
        // applied on didFinish if the article is still loading (e.g. a highlight
        // tap that just mounted this view).
        if scrollToTextToken != coordinator.lastScrollToTextToken {
            coordinator.lastScrollToTextToken = scrollToTextToken
            coordinator.pendingScrollQuery = scrollToTextQuery.isEmpty ? nil : scrollToTextQuery
        }

        if coordinator.loadedArticleKey != articleKey(article) {
            load(article, typography: typography, isDark: isDark, initialProgress: initialProgress, into: webView, coordinator: coordinator)
            return
        }

        if coordinator.lastTypography != typography {
            coordinator.lastTypography = typography
            webView.evaluateJavaScript(ReaderTemplate.typographyUpdateJS(typography), completionHandler: nil)
        }

        if coordinator.lastIsDark != isDark {
            coordinator.lastIsDark = isDark
            webView.evaluateJavaScript(ReaderTemplate.themeUpdateJS(isDark: isDark), completionHandler: nil)
        }

        if let query = coordinator.pendingScrollQuery {
            coordinator.pendingScrollQuery = nil
            let escaped = ReaderTemplate.escapeForJSString(query)
            webView.evaluateJavaScript("window.__groveScrollToText('\(escaped)');", completionHandler: nil)
        }
    }

    private static func articleKey(_ article: ReadableArticle) -> String {
        "\(article.sourceURLString ?? "")#\(article.extractedAt.timeIntervalSince1970)"
    }
}

// MARK: - Coordinator

@MainActor
final class ReaderModeCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var onTextSelected: ((String?) -> Void)?
    var onScrollProgress: ((Double) -> Void)?
    var onOpenExternalLink: ((URL) -> Void)?

    var loadedArticleKey: String? = nil
    var lastTypography: ReaderTypographySettings? = nil
    var lastIsDark: Bool? = nil
    var lastScrollToTextToken = 0
    var pendingScrollQuery: String? = nil
    var pendingRestoreProgress: Double? = nil

    init(
        onTextSelected: ((String?) -> Void)?,
        onScrollProgress: ((Double) -> Void)?,
        onOpenExternalLink: ((URL) -> Void)?
    ) {
        self.onTextSelected = onTextSelected
        self.onScrollProgress = onScrollProgress
        self.onOpenExternalLink = onOpenExternalLink
    }

    // Reader content is a static template — link activations open externally.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            onOpenExternalLink?(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let fraction = pendingRestoreProgress {
            pendingRestoreProgress = nil
            webView.evaluateJavaScript(ReaderTemplate.restoreProgressJS(fraction), completionHandler: nil)
        }
        if let query = pendingScrollQuery {
            pendingScrollQuery = nil
            let escaped = ReaderTemplate.escapeForJSString(query)
            webView.evaluateJavaScript("window.__groveScrollToText('\(escaped)');", completionHandler: nil)
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "selectionChanged":
            if let text = message.body as? String, !text.isEmpty {
                onTextSelected?(text)
            } else {
                onTextSelected?(nil)
            }
        case "readingProgress":
            if let fraction = message.body as? Double {
                onScrollProgress?(fraction)
            } else if let number = message.body as? NSNumber {
                onScrollProgress?(number.doubleValue)
            }
        default:
            break
        }
    }
}
