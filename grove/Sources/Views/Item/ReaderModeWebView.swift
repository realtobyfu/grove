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

    /// Syntax highlighting for block code in Reader mode.
    ///
    /// A small self-contained tokenizer rather than a vendored library: the
    /// reader page is built with `loadHTMLString` and can't reach a CDN, and
    /// the alternative — embedding a full highlighter plus language packs as
    /// another base64 payload — costs far more than the dozen-ish languages
    /// that actually turn up in saved articles.
    ///
    /// Each `<pre>` is re-tokenized from its own `textContent`, so any
    /// highlighting the source site shipped is replaced rather than layered
    /// on. Language comes from a `language-*`/`data-lang` hint when the page
    /// has one and from content heuristics otherwise; an unrecognizable block
    /// is either tokenized conservatively (comments, strings, numbers and
    /// keywords only) or left plain, so console output and log dumps don't get
    /// speckled. Runs at document end, before highlight marks are applied, so
    /// the mark pass sees the final text nodes.
    static let syntaxHighlightJS = """
    (function() {
        var ALIASES = {
            js: 'js', javascript: 'js', jsx: 'js', mjs: 'js', cjs: 'js', node: 'js',
            ts: 'js', typescript: 'js', tsx: 'js', json5: 'js',
            swift: 'swift',
            py: 'py', python: 'py', python3: 'py', ipython: 'py',
            rb: 'rb', ruby: 'rb',
            rs: 'rust', rust: 'rust',
            go: 'go', golang: 'go',
            java: 'java', kotlin: 'java', kt: 'java', scala: 'java', groovy: 'java', dart: 'java',
            c: 'c', h: 'c', cpp: 'c', cc: 'c', hpp: 'c', cxx: 'c',
            objc: 'c', objectivec: 'c', cs: 'c', csharp: 'c',
            php: 'php',
            sh: 'sh', bash: 'sh', zsh: 'sh', shell: 'sh', console: 'sh', terminal: 'sh', fish: 'sh',
            sql: 'sql', postgres: 'sql', postgresql: 'sql', mysql: 'sql', sqlite: 'sql',
            json: 'json', jsonc: 'json',
            yaml: 'yaml', yml: 'yaml', toml: 'yaml',
            html: 'markup', xml: 'markup', svg: 'markup', vue: 'markup', erb: 'markup', jsp: 'markup',
            css: 'css', scss: 'css', sass: 'css', less: 'css',
            text: 'none', plaintext: 'none', plain: 'none', txt: 'none',
            none: 'none', nohighlight: 'none', output: 'none', diff: 'none', markdown: 'none', md: 'none'
        };

        function words(list) {
            var set = {};
            var parts = list.split(' ');
            for (var i = 0; i < parts.length; i++) {
                if (parts[i]) { set[parts[i]] = true; }
            }
            return set;
        }

        function esc(text) {
            return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        }

        function span(cls, text) {
            return '<span class="gtok-' + cls + '">' + esc(text) + '</span>';
        }

        function reEscape(text) {
            return text.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
        }

        function spec(o) {
            return {
                kw: words(o.kw),
                lit: words(o.lit || 'true false null undefined'),
                typ: words(o.typ || ''),
                line: o.line === undefined ? ['//'] : o.line,
                block: o.block !== false,
                triple: !!o.triple,
                single: o.single !== false,
                backtick: !!o.backtick,
                at: !!o.at,
                dollar: !!o.dollar,
                fold: !!o.fold
            };
        }

        var SPECS = {
            js: spec({
                kw: 'abstract as async await break case catch class const continue debugger declare default delete do else enum export extends finally for from function get if implements import in instanceof interface let new of package private protected public readonly return satisfies set static super switch throw try type typeof var void while with yield',
                lit: 'true false null undefined NaN Infinity this globalThis',
                typ: 'Array Object String Number Boolean Promise Map Set WeakMap Date RegExp JSON Math Symbol BigInt Error console window document',
                backtick: true, at: true
            }),
            swift: spec({
                kw: 'actor any as associatedtype async await borrowing break case catch class consuming continue convenience default defer deinit didSet distributed do dynamic else enum extension fallthrough fileprivate final for func get guard if import in indirect infix init inout internal is lazy let macro mutating nonisolated nonmutating open operator override package postfix precedencegroup prefix private protocol public repeat required rethrows return set some static struct subscript super switch throw throws try typealias unowned var weak where while willSet',
                lit: 'true false nil self Self super',
                typ: 'Int Double Float String Bool Character Array Dictionary Set Optional Result Data Date URL UUID Void Any AnyObject Task Error',
                at: true
            }),
            py: spec({
                kw: 'and as assert async await break case class continue def del elif else except finally for from global if import in is lambda match nonlocal not or pass raise return try while with yield',
                lit: 'True False None self cls NotImplemented Ellipsis',
                typ: 'int float str bool list dict set tuple bytes object range type',
                line: ['#'], block: false, triple: true, at: true
            }),
            rb: spec({
                kw: 'alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo rescue retry return then undef unless until when while yield require require_relative attr_accessor attr_reader attr_writer include extend',
                lit: 'true false nil self __FILE__ __dir__',
                line: ['#'], block: false, at: true
            }),
            rust: spec({
                kw: 'as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return static struct super trait type union unsafe use where while',
                lit: 'true false Some None Ok Err self Self',
                typ: 'i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box Rc Arc HashMap'
            }),
            go: spec({
                kw: 'break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var append cap len make new panic recover',
                lit: 'true false nil iota',
                typ: 'int int8 int16 int32 int64 uint uint8 uint32 uint64 float32 float64 byte rune string bool error any'
            }),
            java: spec({
                kw: 'abstract assert boolean break byte case catch char class companion const continue data default do double else enum extends final finally float for fun goto if implements import in init instanceof int interface internal is lateinit long native new object open operator out override package permits private protected public record ref return sealed short static strictfp super suspend switch synchronized this throw throws transient try val var void volatile when while yield',
                lit: 'true false null this super it',
                typ: 'String Integer Long Double Float Boolean List Map Set Object Exception'
            }),
            c: spec({
                kw: 'alignas alignof asm auto base bool break case catch char class const constexpr continue decimal default delegate delete do double dynamic_cast else enum event explicit extern fixed float for foreach friend goto if implicit inline int interface internal lock long mutable namespace new noexcept operator out override params private protected public readonly ref register return sbyte sealed short signed sizeof stackalloc static static_cast string struct switch template this throw try typedef typename uint ulong unchecked union unsafe unsigned ushort using var virtual void volatile while',
                lit: 'true false NULL nullptr null this nil YES NO',
                typ: 'size_t uint8_t uint16_t uint32_t uint64_t int8_t int16_t int32_t int64_t FILE',
                at: true
            }),
            php: spec({
                kw: 'abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enum extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield',
                lit: 'true false null',
                line: ['//', '#'], dollar: true
            }),
            sh: spec({
                kw: 'if then else elif fi for while until do done case esac function in select return break continue local export readonly declare source alias set unset shift trap exit eval exec echo cd',
                lit: 'true false',
                line: ['#'], block: false, dollar: true, backtick: true
            }),
            sql: spec({
                kw: 'select from where group by order having limit offset insert into values update set delete create table alter drop index view join inner left right outer full cross on using as distinct union all and or not null is in like ilike between case when then else end exists count sum avg min max primary key foreign references default constraint unique cascade begin commit rollback transaction with returning asc desc',
                lit: 'null true false',
                line: ['--'], fold: true
            })
        };

        function identClass(sp) {
            return function(word, code, end, loose) {
                var key = sp.fold ? word.toLowerCase() : word;
                if (sp.kw[key]) { return 'kw'; }
                if (sp.lit[key]) { return 'lit'; }
                if (sp.typ[key]) { return 'typ'; }
                if (loose) { return null; }
                if (/^\\s*\\(/.test(code.slice(end, end + 8))) { return 'fn'; }
                if (/^[A-Z][A-Za-z0-9_]*$/.test(word)) { return 'typ'; }
                return null;
            };
        }

        function rulesFor(sp) {
            if (sp.rules) { return sp.rules; }
            var rules = [{ re: /[ \\t\\r\\n]+/y, cls: null }];
            if (sp.block) { rules.push({ re: /\\/\\*[\\s\\S]*?(?:\\*\\/|$)/y, cls: 'com' }); }
            if (sp.line && sp.line.length) {
                var starts = [];
                for (var i = 0; i < sp.line.length; i++) { starts.push(reEscape(sp.line[i])); }
                rules.push({ re: new RegExp('(?:' + starts.join('|') + ')[^\\\\n]*', 'y'), cls: 'com' });
            }
            if (sp.triple) {
                rules.push({ re: /[rbfu]{0,2}(?:\"\"\"[\\s\\S]*?(?:\"\"\"|$)|'''[\\s\\S]*?(?:'''|$))/y, cls: 'str' });
            }
            var strings = ['\"(?:\\\\\\\\.|[^\"\\\\\\\\\\\\n])*\"?'];
            if (sp.single) { strings.push(\"'(?:\\\\\\\\.|[^'\\\\\\\\\\\\n])*'?\"); }
            if (sp.backtick) { strings.push('`(?:\\\\\\\\.|[^`\\\\\\\\])*`?'); }
            rules.push({ re: new RegExp(strings.join('|'), 'y'), cls: 'str' });
            rules.push({ re: /0[xXbBoO][0-9a-fA-F_]+n?|\\d[\\d_]*(?:\\.\\d[\\d_]*)?(?:[eE][+-]?\\d+)?/y, cls: 'num' });
            if (sp.dollar) { rules.push({ re: /\\$\\{[^}]*\\}?|\\$[A-Za-z_]\\w*|\\$[\\d@*#?]/y, cls: 'var' }); }
            if (sp.at) { rules.push({ re: /@[A-Za-z_][\\w.]*/y, cls: 'meta' }); }
            rules.push({ re: /[A-Za-z_$][\\w$]*/y, cls: identClass(sp) });
            rules.push({ re: /[^\\w\\s]/y, cls: null });
            sp.rules = rules;
            return rules;
        }

        // Markup keeps its own rules: '<' is structure here, not an operator,
        // and a tag's name, attributes and values each read differently.
        function renderTag(text) {
            var re = /\"[^\"]*\"|'[^']*'|<\\/?[A-Za-z][\\w:.-]*|[A-Za-z_:][\\w:.-]*(?=\\s*=)/g;
            var out = '';
            var last = 0;
            var m;
            while ((m = re.exec(text)) !== null) {
                out += esc(text.slice(last, m.index));
                var token = m[0];
                if (token.charAt(0) === '\"' || token.charAt(0) === \"'\") {
                    out += span('str', token);
                } else if (token.charAt(0) === '<') {
                    var lead = token.charAt(1) === '/' ? 2 : 1;
                    out += esc(token.slice(0, lead)) + span('tag', token.slice(lead));
                } else {
                    out += span('attr', token);
                }
                last = m.index + token.length;
            }
            return out + esc(text.slice(last));
        }

        SPECS.markup = { rules: [
            { re: /<!--[\\s\\S]*?(?:-->|$)/y, cls: 'com' },
            { re: /<!\\[CDATA\\[[\\s\\S]*?(?:\\]\\]>|$)/y, cls: 'com' },
            { re: /<![A-Za-z][^>]*>?/y, cls: 'com' },
            { re: /<\\/?[A-Za-z][^>]*>?/y, render: renderTag },
            { re: /[^<]+/y, cls: null }
        ] };

        SPECS.css = { rules: [
            { re: /[ \\t\\r\\n]+/y, cls: null },
            { re: /\\/\\*[\\s\\S]*?(?:\\*\\/|$)/y, cls: 'com' },
            { re: /\"(?:\\\\.|[^\"\\\\\\n])*\"?|'(?:\\\\.|[^'\\\\\\n])*'?/y, cls: 'str' },
            { re: /!important|@[-\\w]+/y, cls: 'kw' },
            { re: /#[0-9a-fA-F]{3,8}\\b/y, cls: 'num' },
            { re: /-?\\d[\\d.]*(?:px|em|rem|ex|ch|vh|vw|vmin|vmax|%|s|ms|deg|fr|pt|cm|mm)?/y, cls: 'num' },
            { re: /[-a-zA-Z_][-\\w]*(?=\\s*:)/y, cls: 'attr' },
            { re: /[.#][-\\w]+|::?[-a-zA-Z][-\\w]*/y, cls: 'typ' },
            { re: /[-\\w]+/y, cls: null },
            { re: /[^\\w\\s]/y, cls: null }
        ] };

        SPECS.json = { rules: [
            { re: /[ \\t\\r\\n]+/y, cls: null },
            { re: /\"(?:\\\\.|[^\"\\\\])*\"(?=\\s*:)/y, cls: 'attr' },
            { re: /\"(?:\\\\.|[^\"\\\\])*\"?/y, cls: 'str' },
            { re: /-?\\d[\\d.eE+-]*/y, cls: 'num' },
            { re: /\\b(?:true|false|null)\\b/y, cls: 'lit' },
            { re: /\\/\\/[^\\n]*/y, cls: 'com' },
            { re: /[\\w.+-]+/y, cls: null },
            { re: /[^\\s]/y, cls: null }
        ] };

        SPECS.yaml = { rules: [
            { re: /[ \\t\\r\\n]+/y, cls: null },
            { re: /#[^\\n]*/y, cls: 'com' },
            { re: /\"(?:\\\\.|[^\"\\\\\\n])*\"?|'(?:[^'\\n]|'')*'?/y, cls: 'str' },
            { re: /[-\\w.\\/]+(?=\\s*:(?:\\s|$))/y, cls: 'attr' },
            { re: /---|\\.\\.\\.|&[\\w-]+|\\*[\\w-]+|<</y, cls: 'meta' },
            { re: /\\b(?:true|false|null|yes|no|on|off)\\b/y, cls: 'lit' },
            { re: /-?\\d[\\d._]*(?:[eE][+-]?\\d+)?/y, cls: 'num' },
            { re: /[\\w.\\/-]+/y, cls: null },
            { re: /[^\\s]/y, cls: null }
        ] };

        function render(code, sp, loose) {
            var rules = rulesFor(sp);
            var out = '';
            var i = 0;
            var n = code.length;
            while (i < n) {
                var hit = null;
                for (var r = 0; r < rules.length; r++) {
                    var rule = rules[r];
                    rule.re.lastIndex = i;
                    var m = rule.re.exec(code);
                    if (m && m[0].length) { hit = { rule: rule, text: m[0] }; break; }
                }
                if (hit === null) {
                    out += esc(code.charAt(i));
                    i += 1;
                    continue;
                }
                var end = i + hit.text.length;
                if (hit.rule.render) {
                    out += hit.rule.render(hit.text);
                } else {
                    var cls = typeof hit.rule.cls === 'function'
                        ? hit.rule.cls(hit.text, code, end, loose)
                        : hit.rule.cls;
                    out += cls ? span(cls, hit.text) : esc(hit.text);
                }
                i = end;
            }
            return out;
        }

        // Language hint from the markup: 'language-swift', 'lang-py',
        // 'data-lang', or a bare 'ruby' class.
        function fromMarkup(el) {
            if (!el || !el.getAttribute) { return null; }
            var raw = (el.getAttribute('class') || '') + ' '
                + (el.getAttribute('data-lang') || '') + ' '
                + (el.getAttribute('data-language') || '');
            var parts = raw.toLowerCase().split(/[\\s:_+-]+/);
            for (var i = 0; i < parts.length; i++) {
                var part = parts[i];
                if (!part || part === 'language' || part === 'lang' || part === 'highlight'
                    || part === 'sourcecode' || part === 'brush' || part === 'hljs') { continue; }
                if (ALIASES[part]) { return ALIASES[part]; }
            }
            return null;
        }

        function detect(code) {
            var head = code.slice(0, 4000);
            if (/^\\s*[{[]/.test(head) && /\"\\s*:/.test(head) && !/\\bfunction\\b|=>/.test(head)) { return 'json'; }
            if (/^\\s*<[!a-zA-Z\\/]/.test(head) && /<\\/[a-zA-Z]|\\/>/.test(head)) { return 'markup'; }
            if (/^#!.*\\b(?:ba|z)?sh\\b/.test(head) || /^\\s*\\$ \\S/m.test(head)) { return 'sh'; }
            if (/^\\s*(?:@|from |import |def |class )\\w/m.test(head) && /:\\s*$/m.test(head)) { return 'py'; }
            if (/\\bdef \\w+\\(|\\bself\\b|\\bprint\\(/.test(head) && !/[;{]\\s*$/m.test(head)) { return 'py'; }
            // Go before Swift: both spell it 'func', but ':=' and
            // 'package main' belong to Go alone.
            if (/\\bpackage main\\b|:=/.test(head)) { return 'go'; }
            if (/\\bfunc \\w+\\(|@State|import (?:SwiftUI|Foundation)|\\bguard\\b.*\\belse\\b/.test(head)) { return 'swift'; }
            if (/\\bfn \\w+\\(|\\blet mut\\b|\\bimpl\\b|::\\w/.test(head)) { return 'rust'; }
            if (/#include|std::|\\bprintf\\(/.test(head)) { return 'c'; }
            if (/\\b(?:public|private)\\s+(?:static\\s+)?(?:class|void|int)\\b|System\\.out/.test(head)) { return 'java'; }
            if (/<\\?php|\\$\\w+\\s*=\\s*/.test(head) && /\\$/.test(head)) { return 'php'; }
            if (/^\\s*(?:SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|WITH)\\b/i.test(head)) { return 'sql'; }
            if (/[.#]?[-\\w]+\\s*\\{[^}]*:[^}]*;/.test(head)) { return 'css'; }
            // 'Warning: something happened' is a log line, not a mapping, so
            // YAML needs more than one key before it claims the block.
            var keyed = head.match(/^[ \\t-]*[\\w.-]+:(?: |$)/gm);
            if (keyed && keyed.length > 1 && !/[;{}()]/.test(head)) { return 'yaml'; }
            if (/\\b(?:function|const|let|var|require\\(|console\\.)|=>/.test(head)) { return 'js'; }
            return null;
        }

        function run() {
            var blocks = document.querySelectorAll('.grove-content pre');
            for (var i = 0; i < blocks.length; i++) {
                var pre = blocks[i];
                try {
                    var el = pre.querySelector('code') || pre;
                    if (el.getAttribute('data-grove-hl')) { continue; }
                    var code = el.textContent || '';
                    // Very long blocks are rare and the scan is linear per
                    // character; skip rather than stall the first paint.
                    if (!code.trim() || code.length > 60000) { continue; }
                    var lang = fromMarkup(el) || fromMarkup(pre);
                    var loose = false;
                    if (!lang) {
                        lang = detect(code);
                        if (!lang) {
                            // Nothing identified it. Console output, logs and
                            // prose-in-a-box all land here; only tokenize when
                            // the block carries real code punctuation (English
                            // is full of 'if', 'for' and 'in'), and then
                            // without the capitalized-identifier guesswork.
                            var codeish = code.match(/[{};=]|=>/g);
                            if (!codeish || codeish.length < 3) { continue; }
                            lang = 'js';
                            loose = true;
                        }
                    }
                    if (lang === 'none') { continue; }
                    var sp = SPECS[lang];
                    if (!sp) { continue; }
                    el.innerHTML = render(code, sp, loose);
                    el.setAttribute('data-grove-hl', lang);
                } catch (e) { /* a block that won't tokenize stays plain */ }
            }
        }

        window.__groveHighlightCode = run;
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', run);
        } else {
            run();
        }
    })();
    """

    // MARK: Page

    /// The full variable set for one color scheme. Emitted into every scheme
    /// selector below so light/dark stay in step from a single source.
    ///
    /// Syntax colors are the one place Grove spends color: code is read as
    /// structure, not prose, and readers expect keywords, strings, and
    /// comments to separate. The hues are muted print inks rather than the
    /// saturated terminal palette, so a block still sits quietly on the page.
    private static func paletteCSS(dark: Bool) -> String {
        dark ? """
            --bg: #111111;
            --fg: #E8E8E8;
            --fg-secondary: #9E9E9E;
            --border: #222222;
            --code-bg: #1C1C1C;
            --highlight-wash: rgba(255, 255, 255, 0.14);
            --tok-com: #7C8078;
            --tok-str: #A3C98C;
            --tok-num: #D9A96B;
            --tok-kw: #D98FB4;
            --tok-typ: #7FBFC9;
            --tok-fn: #90AEE0;
            --tok-attr: #C8B98F;
            --tok-meta: #B3A6E0;
        """ : """
            --bg: #FAFAFA;
            --fg: #1A1A1A;
            --fg-secondary: #666666;
            --border: #EBEBEB;
            --code-bg: #F0F0EE;
            --highlight-wash: rgba(0, 0, 0, 0.08);
            --tok-com: #8C8C84;
            --tok-str: #4A7A3F;
            --tok-num: #97591F;
            --tok-kw: #8A3D62;
            --tok-typ: #2C6472;
            --tok-fn: #35548C;
            --tok-attr: #6E5A24;
            --tok-meta: #6C5CA6;
        """
    }

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
        \(paletteCSS(dark: false))
        }
        @media (prefers-color-scheme: dark) {
            :root {
            \(paletteCSS(dark: true))
            }
        }
        :root[data-grove-theme="light"] {
        \(paletteCSS(dark: false))
        }
        :root[data-grove-theme="dark"] {
        \(paletteCSS(dark: true))
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
        /* Syntax tokens, written by __groveHighlightCode. Only block code is
           tokenized; inline <code> in prose stays plain ink. */
        .grove-content pre .gtok-com { color: var(--tok-com); font-style: italic; }
        .grove-content pre .gtok-str { color: var(--tok-str); }
        .grove-content pre .gtok-num,
        .grove-content pre .gtok-lit { color: var(--tok-num); }
        .grove-content pre .gtok-kw { color: var(--tok-kw); }
        .grove-content pre .gtok-typ,
        .grove-content pre .gtok-tag { color: var(--tok-typ); }
        .grove-content pre .gtok-fn { color: var(--tok-fn); }
        .grove-content pre .gtok-attr { color: var(--tok-attr); }
        .grove-content pre .gtok-meta,
        .grove-content pre .gtok-var { color: var(--tok-meta); }
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
        // Ahead of the highlight-mark script so code blocks are already
        // tokenized when saved highlights are wrapped into their text nodes.
        userContentController.addUserScript(WKUserScript(
            source: ReaderTemplate.syntaxHighlightJS,
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
        coordinator.pendingRestoreProgress = restorableProgress(initialProgress)
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
        guard let pass = highlightPass(
            desired: coordinator.desiredHighlights,
            previous: coordinator.lastAppliedHighlights
        ) else { return }
        coordinator.lastAppliedHighlights = pass.highlights
        webView.evaluateJavaScript(
            ReaderTemplate.applyHighlightsJS(pass.highlights, animated: pass.animated),
            completionHandler: nil
        )
    }

    /// What one highlight pass should inject, or nil when the document already
    /// carries exactly `desired`. `previous` is the set last injected into this
    /// document — nil on its first pass, when nothing animates; afterwards only
    /// strings absent from `previous` ink in.
    nonisolated static func highlightPass(
        desired: [String],
        previous: [String]?
    ) -> (highlights: [String], animated: [String])? {
        if let previous, previous == desired { return nil }
        let animated = previous.map { prior in desired.filter { !prior.contains($0) } } ?? []
        return (desired, animated)
    }

    /// The saved scroll fraction worth restoring on load, or nil to start at
    /// the top. Fractions within 1% of either end are not restored.
    nonisolated static func restorableProgress(_ fraction: Double) -> Double? {
        (fraction > 0.01 && fraction < 0.99) ? fraction : nil
    }

    /// Identity of one extraction: a re-extraction of the same page is a new
    /// document and reloads, while typography/theme changes update in place.
    nonisolated static func articleKey(_ article: ReadableArticle) -> String {
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
