import Foundation

/// Find-in-article: the decisions and the text matching that need no view.
///
/// Everything here is pure, so the rules — where ⌘F goes, what the bar says,
/// how matches are counted, how stepping wraps — can be tested at their edges
/// without a web view or a window.
enum ReaderFind {

    // MARK: - ⌘F Routing

    /// What the Find shortcut reaches.
    enum ShortcutTarget: Equatable, Sendable {
        /// The find bar of the reader on screen.
        case article
        /// The library-wide search overlay.
        case library
    }

    /// Where ⌘F goes.
    ///
    /// The article wins only while an item is open on a surface that can
    /// search itself (the web pane or the PDF pane). Everywhere else ⌘F is
    /// library search — including while the search or capture overlay is
    /// already up over a reader, where ⌘F keeps toggling search as it always
    /// has rather than reaching for a find bar hidden underneath.
    static func shortcutTarget(
        readerIsOpen: Bool,
        surfaceCanFind: Bool,
        overlayIsUp: Bool
    ) -> ShortcutTarget {
        if readerIsOpen && surfaceCanFind && !overlayIsUp {
            return .article
        }
        return .library
    }

    // MARK: - Status

    /// What a reading surface knows about the current query.
    enum Status: Equatable, Sendable {
        /// Nothing has been searched for yet.
        case idle
        case noMatches
        /// `current` is the 1-based position of the match on screen. It is
        /// only ever set by a surface that owns the whole ordered match list
        /// (PDF); the web surfaces step through WebKit's own find and report
        /// a count alone, because a position there could not be kept true.
        case matches(count: Int, current: Int?)
        /// A match is on screen but the surface could not count them.
        case found
    }

    /// The find bar's count text.
    static func label(for status: Status) -> String {
        switch status {
        case .idle:
            return ""
        case .noMatches:
            return "No matches"
        case .found:
            return "Found"
        case .matches(let count, let current):
            guard count > 0 else { return "No matches" }
            if let current, current >= 1, current <= count {
                return "\(current) of \(count)"
            }
            return count == 1 ? "1 match" : "\(count) matches"
        }
    }

    /// The status a web surface reports. WebKit's find is the authority on
    /// whether anything matched at all; the count over the page text only
    /// decorates a hit and never contradicts a miss.
    static func webStatus(matchFound: Bool, counted: Int?) -> Status {
        guard matchFound else { return .noMatches }
        guard let counted, counted > 0 else { return .found }
        return .matches(count: counted, current: nil)
    }

    // MARK: - Stepping

    /// The match index a step lands on, wrapping at both ends. With no
    /// current match a forward step starts at the first and a backward step
    /// at the last; nil when there is nothing to step through.
    static func steppedIndex(from current: Int?, count: Int, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let current, current >= 0, current < count else {
            return forward ? 0 : count - 1
        }
        return forward ? (current + 1) % count : (current - 1 + count) % count
    }

    // MARK: - Counting

    /// Characters WebKit's find treats as interchangeable: typographic quotes
    /// match straight ones, a no-break space matches a space, and a soft
    /// hyphen is not there at all.
    private static let foldTable: [(from: String, to: String)] = [
        ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201A}", "'"),
        ("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{201E}", "\""),
        ("\u{00A0}", " "),
        ("\u{00AD}", ""),
    ]

    /// `text` with those characters folded. Case and accents are left to the
    /// comparison itself.
    static func searchFolded(_ text: String) -> String {
        var folded = text
        for entry in foldTable where folded.contains(entry.from) {
            folded = folded.replacingOccurrences(of: entry.from, with: entry.to)
        }
        return folded
    }

    /// Case never matters. An unaccented query also matches accented text
    /// ("resume" finds "résumé"), but a query typed with accents asks for
    /// them — the same asymmetry as WebKit's own find.
    private static func compareOptions(forFoldedQuery needle: String) -> NSString.CompareOptions {
        var options: NSString.CompareOptions = [.caseInsensitive, .widthInsensitive]
        if needle.folding(options: .diacriticInsensitive, locale: nil) == needle {
            options.insert(.diacriticInsensitive)
        }
        return options
    }

    /// How many times `query` occurs in `text`: case-insensitive, counted
    /// left to right without overlap ("aa" occurs twice in "aaaa").
    static func occurrenceCount(of query: String, in text: String) -> Int {
        occurrenceCount(of: query, inFolded: searchFolded(text))
    }

    /// The same count over text already passed through `searchFolded`, for a
    /// caller that keeps one page's text across several queries.
    static func occurrenceCount(of query: String, inFolded haystack: String) -> Int {
        let needle = searchFolded(query)
        guard !needle.isEmpty, !haystack.isEmpty else { return 0 }
        let source = haystack as NSString
        let options = compareOptions(forFoldedQuery: needle)
        var count = 0
        var remaining = NSRange(location: 0, length: source.length)
        while remaining.length > 0 {
            let found = source.range(of: needle, options: options, range: remaining)
            // A zero-length hit would never advance; treat it as the end.
            guard found.location != NSNotFound, found.length > 0 else { break }
            count += 1
            let next = found.location + found.length
            remaining = NSRange(location: next, length: source.length - next)
        }
        return count
    }

    // MARK: - Selection Ownership

    /// Whether a selection reported by the page is just the match find put
    /// there. WebKit shows a match by selecting it, and the reader raises its
    /// Highlight bar for any selection — so the two have to be told apart, or
    /// every keystroke in the find field would summon that bar.
    ///
    /// The compare ignores case, accents and how whitespace happens to be
    /// laid out, which is how a match can differ from the text typed for it.
    static func isFindSelection(_ selection: String?, query: String) -> Bool {
        guard let selection else { return false }
        let needle = collapsingWhitespace(searchFolded(query))
        guard !needle.isEmpty else { return false }
        let candidate = collapsingWhitespace(searchFolded(selection))
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        return candidate.compare(needle, options: options) == .orderedSame
    }

    /// `text` trimmed, with every run of whitespace reduced to one space.
    private static func collapsingWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Page Scripts
    //
    // Find never changes the document. Reader mode anchors the user's saved
    // highlights by text offsets into the DOM, so wrapping matches in <mark>
    // elements — the usual JavaScript find — would put that anchoring at risk.
    // These read the page, or move its selection, and nothing else.

    /// The page's rendered text, for counting. `innerText` leaves out what the
    /// page hides, which is also what WebKit's find skips.
    static let pageTextJS = """
    (function() {
        try {
            var body = document.body;
            if (!body) { return ''; }
            var text = body.innerText;
            return (typeof text === 'string') ? text : (body.textContent || '');
        } catch (e) { return ''; }
    })();
    """

    /// Collapses the selection to its own start. WebKit searches onward from
    /// the *end* of the selection, so without this a query refined by one more
    /// letter would skip the match it is already sitting on.
    static let anchorSelectionJS = """
    (function() {
        try {
            var selection = window.getSelection();
            if (selection && selection.rangeCount > 0 && !selection.isCollapsed) {
                selection.collapseToStart();
            }
        } catch (e) { }
        return true;
    })();
    """

    /// The current selection as text ("" when there is none).
    static let selectionTextJS = """
    (function() {
        try {
            var selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) { return ''; }
            return String(selection.toString());
        } catch (e) { return ''; }
    })();
    """

    /// Drops the selection.
    static let clearSelectionJS = """
    (function() {
        try {
            var selection = window.getSelection();
            if (selection) { selection.removeAllRanges(); }
        } catch (e) { }
        return true;
    })();
    """
}
