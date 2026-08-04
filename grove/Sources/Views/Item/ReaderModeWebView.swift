import SwiftUI
import WebKit

// MARK: - Web Selection Geometry

/// Where a web-view text selection sits on screen, as reported by the shared
/// selection-reporter script. `rect` is in CSS viewport coordinates and
/// `viewport` is the size those coordinates are relative to — the two travel
/// together so the app can map them onto its own pane even when the web view
/// is zoomed (macOS `pageZoom`) or laid out at a different scale.
struct WebSelectionGeometry: Equatable, Sendable {
    var rect: CGRect
    var viewport: CGSize

    /// The selection rect expressed in the coordinate space of a pane of the
    /// given width. The web view fills the pane, so a single width ratio maps
    /// both axes.
    func rect(inPaneOfWidth paneWidth: CGFloat) -> CGRect {
        guard viewport.width > 0, paneWidth > 0 else { return rect }
        let scale = paneWidth / viewport.width
        return CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// Decodes a `selectionChanged` message body posted by
    /// `ReaderTemplate.selectionReporterJS`. Tolerates the older plain-string
    /// payload so a stale injected script can never crash the handler.
    static func decode(_ body: Any) -> (text: String?, geometry: WebSelectionGeometry?) {
        if let text = body as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed.isEmpty ? nil : trimmed, nil)
        }
        guard let dict = body as? [String: Any] else { return (nil, nil) }
        let rawText = (dict["text"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawText.isEmpty else { return (nil, nil) }
        guard let rect = dict["rect"] as? [String: Any],
              let viewport = dict["viewport"] as? [String: Any],
              let x = number(rect["x"]), let y = number(rect["y"]),
              let width = number(rect["width"]), let height = number(rect["height"]),
              let vw = number(viewport["width"]), let vh = number(viewport["height"]),
              vw > 0
        else { return (rawText, nil) }
        return (
            rawText,
            WebSelectionGeometry(
                rect: CGRect(x: x, y: y, width: width, height: height),
                viewport: CGSize(width: vw, height: vh)
            )
        )
    }

    private static func number(_ value: Any?) -> CGFloat? {
        guard let number = value as? NSNumber else { return nil }
        return CGFloat(number.doubleValue)
    }
}

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
    /// What "Reset" returns to — the same value a fresh install starts at.
    static let defaultSizeStep = 1
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

    /// Debounced selection reporter, shared verbatim by every web surface so
    /// the message contract can't drift between Reader mode and live pages.
    /// Posts `{ text, rect, viewport }` to `handler`: `text` is the trimmed
    /// selection ("" when there is none), `rect` the selection's bounding box
    /// in CSS viewport coordinates (null for a collapsed or zero-area
    /// selection), and `viewport` the size those coordinates are relative to.
    ///
    /// Scrolling moves the selection out from under the anchored action bar,
    /// so a short scroll debounce re-reports the (now moved) rect rather than
    /// leaving a bar floating over nothing.
    static func selectionReporterJS(handler: String) -> String {
        """
        (function() {
            var HANDLER = '\(handler)';
            var selectionTimer = null;
            var scrollTimer = null;
            var lastPayload = '';
            function currentPayload() {
                var empty = { text: '', rect: null, viewport: null };
                try {
                    var sel = window.getSelection();
                    if (!sel || sel.rangeCount === 0) { return empty; }
                    var text = sel.toString().trim();
                    if (!text) { return empty; }
                    var r = sel.getRangeAt(0).getBoundingClientRect();
                    // A collapsed selection (caret) reports a zero-area rect;
                    // send the text without geometry rather than anchoring the
                    // bar to a point that means nothing.
                    var rect = (r && (r.width > 0 || r.height > 0))
                        ? { x: r.left, y: r.top, width: r.width, height: r.height }
                        : null;
                    return {
                        text: text,
                        rect: rect,
                        viewport: { width: window.innerWidth, height: window.innerHeight }
                    };
                } catch (e) {
                    return empty;
                }
            }
            function report() {
                try {
                    var payload = currentPayload();
                    var key = JSON.stringify(payload);
                    // Selection events fire far more often than the selection
                    // actually changes; don't wake the app for a repeat.
                    if (key === lastPayload) { return; }
                    lastPayload = key;
                    window.webkit.messageHandlers[HANDLER].postMessage(payload);
                } catch (e) { /* fail silent */ }
            }
            function debouncedReport() {
                clearTimeout(selectionTimer);
                selectionTimer = setTimeout(report, 150);
            }
            document.addEventListener('mouseup', debouncedReport);
            document.addEventListener('keyup', debouncedReport);
            document.addEventListener('selectionchange', debouncedReport);
            window.addEventListener('scroll', function() {
                clearTimeout(scrollTimer);
                scrollTimer = setTimeout(report, 80);
            }, { passive: true });
        })();
        """
    }

    /// Persistent highlight marks for Reader mode.
    /// `window.__groveApplyHighlights(list, animated)` clears every existing
    /// `mark.grove-highlight` and re-wraps the first match of each string in
    /// `list`; strings in `animated` additionally get the one-shot ink-in
    /// class. Strings that no longer match (content drift) are skipped
    /// silently. Returns the number of strings that were marked.
    ///
    /// Matching ignores whitespace entirely: a quote selected across a
    /// paragraph break carries newlines the concatenated DOM text does not,
    /// so an exact compare would miss most multi-block highlights.
    static let highlightMarksJS = """
    (function() {
        function collect() {
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
            var nodes = [];
            var full = '';
            while (walker.nextNode()) {
                var node = walker.currentNode;
                var p = node.parentElement;
                if (!p) { continue; }
                var tag = p.tagName;
                if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') { continue; }
                if (!node.textContent.length) { continue; }
                nodes.push({ node: node, start: full.length });
                full += node.textContent;
            }
            return { nodes: nodes, full: full };
        }

        function strip(text) {
            var out = '';
            var map = [];
            for (var i = 0; i < text.length; i++) {
                var ch = text[i];
                if (/\\s/.test(ch)) { continue; }
                out += ch.toLowerCase();
                map.push(i);
            }
            return { text: out, map: map };
        }

        function wrapFirstMatch(query, animate) {
            var collected = collect();
            if (!collected.nodes.length) { return 0; }
            var haystack = strip(collected.full);
            var needle = strip(query).text;
            if (!needle) { return 0; }
            var at = haystack.text.indexOf(needle);
            if (at === -1) { return 0; }
            var startIdx = haystack.map[at];
            var endIdx = haystack.map[at + needle.length - 1] + 1;
            var cls = animate ? 'grove-highlight grove-highlight--new' : 'grove-highlight';
            var created = 0;
            var nodes = collected.nodes;
            for (var i = 0; i < nodes.length; i++) {
                var entry = nodes[i];
                var len = entry.node.textContent.length;
                var nodeStart = entry.start;
                if (nodeStart + len <= startIdx || nodeStart >= endIdx) { continue; }
                var s = Math.max(0, startIdx - nodeStart);
                var e = Math.min(len, endIdx - nodeStart);
                if (e <= s) { continue; }
                var target = entry.node;
                if (s > 0) { target = target.splitText(s); }
                if (target.textContent.length > e - s) { target.splitText(e - s); }
                var parent = target.parentNode;
                if (!parent) { continue; }
                var mark = document.createElement('mark');
                mark.className = cls;
                parent.replaceChild(mark, target);
                mark.appendChild(target);
                created++;
            }
            return created;
        }

        window.__groveApplyHighlights = function(list, animated) {
            try {
                var old = document.querySelectorAll('mark.grove-highlight');
                for (var i = 0; i < old.length; i++) {
                    var mark = old[i];
                    var parent = mark.parentNode;
                    if (!parent) { continue; }
                    while (mark.firstChild) { parent.insertBefore(mark.firstChild, mark); }
                    parent.removeChild(mark);
                    parent.normalize();
                }
                if (!list || !list.length) { return 0; }
                var fresh = {};
                for (var a = 0; a < (animated || []).length; a++) { fresh[animated[a]] = true; }
                var applied = 0;
                var didAnimate = false;
                for (var j = 0; j < list.length; j++) {
                    var query = list[j];
                    if (!query) { continue; }
                    var animate = fresh[query] === true;
                    if (wrapFirstMatch(query, animate) > 0) {
                        applied++;
                        if (animate) { didAnimate = true; }
                    }
                }
                if (didAnimate) {
                    // The class is one-shot; drop it once the keyframe has run
                    // so a later re-render doesn't replay the ink-in.
                    setTimeout(function() {
                        var marks = document.querySelectorAll('mark.grove-highlight--new');
                        for (var k = 0; k < marks.length; k++) {
                            marks[k].classList.remove('grove-highlight--new');
                        }
                    }, 450);
                }
                return applied;
            } catch (e) {
                return 0;
            }
        };
    })();
    """

    /// Call into `__groveApplyHighlights` with the item's saved highlights.
    /// `animated` are the ones that should ink in (a highlight the user just
    /// created); everything else appears already washed.
    static func applyHighlightsJS(_ highlights: [String], animated: [String]) -> String {
        func jsArray(_ values: [String]) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: values),
                  let encoded = String(data: data, encoding: .utf8) else { return "[]" }
            return encoded
        }
        return """
        window.__groveApplyHighlights && window.__groveApplyHighlights(\(jsArray(highlights)), \(jsArray(animated)));
        """
    }

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
            --highlight-wash: rgba(0, 0, 0, 0.08);
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #111111;
                --fg: #E8E8E8;
                --fg-secondary: #9E9E9E;
                --border: #222222;
                --code-bg: #1C1C1C;
                --highlight-wash: rgba(255, 255, 255, 0.14);
            }
        }
        :root[data-grove-theme="light"] {
            --bg: #FAFAFA;
            --fg: #1A1A1A;
            --fg-secondary: #666666;
            --border: #EBEBEB;
            --code-bg: #F0F0EE;
            --highlight-wash: rgba(0, 0, 0, 0.08);
        }
        :root[data-grove-theme="dark"] {
            --bg: #111111;
            --fg: #E8E8E8;
            --fg-secondary: #9E9E9E;
            --border: #222222;
            --code-bg: #1C1C1C;
            --highlight-wash: rgba(255, 255, 255, 0.14);
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
        /* Saved highlights: an ink wash, never a color. Text is untouched. */
        mark.grove-highlight {
            background-color: var(--highlight-wash);
            color: inherit;
            border-radius: 2px;
            padding: 0 0.05em;
            -webkit-box-decoration-break: clone;
            box-decoration-break: clone;
        }
        /* One-shot ink-in for a highlight the reader just made: the wash
           floods left to right, then the class is dropped and the plain
           background above takes over. */
        mark.grove-highlight--new {
            background-color: transparent;
            background-image: linear-gradient(var(--highlight-wash), var(--highlight-wash));
            background-repeat: no-repeat;
            background-position: left center;
            background-size: 0% 100%;
            animation: grove-ink-in 350ms ease-out forwards;
        }
        @keyframes grove-ink-in {
            from { background-size: 0% 100%; }
            to { background-size: 100% 100%; }
        }
        @media (prefers-reduced-motion: reduce) {
            mark.grove-highlight--new {
                animation: none;
                background-color: var(--highlight-wash);
                background-image: none;
            }
        }
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
    /// Saved highlight strings for the item backing this page, rendered as
    /// persistent `<mark>` washes in the article.
    var highlights: [String] = []
    var onTextSelected: ((String?) -> Void)?
    var onSelectionGeometry: ((WebSelectionGeometry?) -> Void)?
    var onScrollProgress: ((Double) -> Void)?
    var onOpenExternalLink: ((URL) -> Void)?

    func makeCoordinator() -> ReaderModeCoordinator {
        ReaderModeCoordinator(
            onTextSelected: onTextSelected,
            onSelectionGeometry: onSelectionGeometry,
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
            highlights: highlights,
            onTextSelected: onTextSelected,
            onSelectionGeometry: onSelectionGeometry,
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
    /// Saved highlight strings for the item backing this page, rendered as
    /// persistent `<mark>` washes in the article.
    var highlights: [String] = []
    var onTextSelected: ((String?) -> Void)?
    var onSelectionGeometry: ((WebSelectionGeometry?) -> Void)?
    var onScrollProgress: ((Double) -> Void)?
    var onOpenExternalLink: ((URL) -> Void)?

    func makeCoordinator() -> ReaderModeCoordinator {
        ReaderModeCoordinator(
            onTextSelected: onTextSelected,
            onSelectionGeometry: onSelectionGeometry,
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
            highlights: highlights,
            onTextSelected: onTextSelected,
            onSelectionGeometry: onSelectionGeometry,
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
            source: ReaderTemplate.selectionReporterJS(handler: "selectionChanged"),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        userContentController.addUserScript(WKUserScript(
            source: ReaderTemplate.highlightMarksJS,
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
        // Extracted articles keep their footnote/endnote links, and those come
        // through as target="_blank" often enough that without a UI delegate
        // WebKit silently drops the click.
        webView.uiDelegate = coordinator
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
        // A fresh document carries no marks yet; the first pass after didFinish
        // renders the saved highlights without the ink-in animation.
        coordinator.lastAppliedHighlights = nil
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
        highlights: [String],
        onTextSelected: ((String?) -> Void)?,
        onSelectionGeometry: ((WebSelectionGeometry?) -> Void)?,
        onScrollProgress: ((Double) -> Void)?,
        onOpenExternalLink: ((URL) -> Void)?
    ) {
        coordinator.onTextSelected = onTextSelected
        coordinator.onSelectionGeometry = onSelectionGeometry
        coordinator.onScrollProgress = onScrollProgress
        coordinator.onOpenExternalLink = onOpenExternalLink
        // Held on the coordinator so didFinish can render them even when the
        // highlights arrived while the document was still loading.
        coordinator.desiredHighlights = highlights

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

        applyHighlights(webView, coordinator: coordinator)
    }

    /// Re-marks the article whenever the saved highlight set changes. The whole
    /// set is re-applied each time — deleting a reflection therefore drops its
    /// mark on the next pass, with no incremental bookkeeping to keep in sync.
    /// Strings that are new since the previous pass ink in; on the first pass
    /// after a load nothing animates.
    static func applyHighlights(
        _ webView: WKWebView,
        coordinator: ReaderModeCoordinator,
        documentIsReady: Bool = false
    ) {
        // Injecting before the document is up would silently no-op and, worse,
        // record the set as applied. didFinish passes documentIsReady.
        guard documentIsReady || !webView.isLoading else { return }
        let desired = coordinator.desiredHighlights
        let previous = coordinator.lastAppliedHighlights
        if let previous, previous == desired { return }
        let animated = previous.map { prior in desired.filter { !prior.contains($0) } } ?? []
        coordinator.lastAppliedHighlights = desired
        webView.evaluateJavaScript(
            ReaderTemplate.applyHighlightsJS(desired, animated: animated),
            completionHandler: nil
        )
    }

    private static func articleKey(_ article: ReadableArticle) -> String {
        "\(article.sourceURLString ?? "")#\(article.extractedAt.timeIntervalSince1970)"
    }
}

// MARK: - Coordinator

@MainActor
final class ReaderModeCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var onTextSelected: ((String?) -> Void)?
    var onSelectionGeometry: ((WebSelectionGeometry?) -> Void)?
    var onScrollProgress: ((Double) -> Void)?
    var onOpenExternalLink: ((URL) -> Void)?

    var loadedArticleKey: String? = nil
    var lastTypography: ReaderTypographySettings? = nil
    var lastIsDark: Bool? = nil
    var lastScrollToTextToken = 0
    var pendingScrollQuery: String? = nil
    var pendingRestoreProgress: Double? = nil
    /// Highlight strings the view wants marked in the current document.
    var desiredHighlights: [String] = []
    /// What was last actually injected — nil until the first pass on a
    /// freshly loaded document, which is what keeps old highlights from
    /// animating in on arrival.
    var lastAppliedHighlights: [String]? = nil

    init(
        onTextSelected: ((String?) -> Void)?,
        onSelectionGeometry: ((WebSelectionGeometry?) -> Void)?,
        onScrollProgress: ((Double) -> Void)?,
        onOpenExternalLink: ((URL) -> Void)?
    ) {
        self.onTextSelected = onTextSelected
        self.onSelectionGeometry = onSelectionGeometry
        self.onScrollProgress = onScrollProgress
        self.onOpenExternalLink = onOpenExternalLink
    }

    // Reader content is a static template — link activations hand off to the
    // pane's live web view. In-page anchors are the exception: footnote and
    // table-of-contents links belong to this document and must scroll here
    // rather than kick the reader out to the network.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            if Self.isSameDocumentAnchor(url, in: webView) {
                decisionHandler(.allow)
                return
            }
            onOpenExternalLink?(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // target="_blank" / window.open: the reader has nowhere to put a new web
    // view, so route the URL through the same in-pane navigation path.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            onOpenExternalLink?(url)
        }
        return nil
    }

    /// True when `url` is this document with only a fragment appended.
    private static func isSameDocumentAnchor(_ url: URL, in webView: WKWebView) -> Bool {
        guard url.fragment != nil, let current = webView.url else { return false }
        func withoutFragment(_ url: URL) -> String {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            return components?.string ?? url.absoluteString
        }
        return withoutFragment(url) == withoutFragment(current)
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
        ReaderModeSupport.applyHighlights(webView, coordinator: self, documentIsReady: true)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "selectionChanged":
            let selection = WebSelectionGeometry.decode(message.body)
            onTextSelected?(selection.text)
            onSelectionGeometry?(selection.geometry)
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
