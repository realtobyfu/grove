import Foundation

// The Library as the place you search: the pure rules that turn what
// `SearchViewModel` found into the groups the Library lists while there is a
// query in the find field, and the one-line snippet shown around a match.
// The search itself is `SearchViewModel`'s; nothing is scored or ranked here
// beyond deciding which heading a hit belongs under. Covered by
// LibraryFindTests.

enum LibraryFind {

    // MARK: - Groups

    /// The headings of the Library's find results, in display order.
    enum GroupKind: String, CaseIterable, Sendable {
        /// The query is in the item's title.
        case titles
        /// The query is in something the user wrote: a note's body or a reflection.
        case notes
        /// The query is in the saved text of something the user did not write.
        case text
        /// The query is in the name of a tag the item carries.
        case tagged
        /// Nothing matches literally; the embedding index places it nearby.
        case related

        var title: String {
            switch self {
            case .titles: "Titles"
            case .notes: "In your notes and reflections"
            case .text: "In the text"
            case .tagged: "Tagged"
            case .related: "Related in meaning"
            }
        }
    }

    /// Where a hit came from in `SearchViewModel`'s results.
    enum Source: Sendable {
        case item
        case reflection
        /// An item carrying a tag the search found. Its candidate's `body`
        /// is the tag's name.
        case tag
    }

    /// The heading and identity of the board rows, which offer a board's
    /// filter chip rather than an item, and so sit outside `GroupKind`.
    static let boardsGroupID = "boards"
    static let boardsGroupTitle = "Boards"

    /// One search hit, reduced to what grouping needs. `payload` is carried
    /// through untouched (the Library passes the `SearchResult`).
    struct Candidate<Payload> {
        /// Unique per hit: two reflections on one item are two candidates.
        let id: String
        /// The item the hit opens (a reflection's parent item).
        let itemID: UUID
        let source: Source
        /// The item's title.
        let title: String
        /// True for a note the user wrote, which files its text matches
        /// under `.notes` rather than `.text`.
        let isNote: Bool
        /// The text a snippet is cut from: a reflection's content, or an
        /// item's note body / saved text, as stored (Markdown marks are
        /// taken off here). Empty when there is none. For a `.tag` hit, the
        /// tag's name.
        let body: String
        let score: Double
        let payload: Payload
    }

    struct Row<Payload>: Identifiable {
        let id: String
        let itemID: UUID
        let source: Source
        /// The line under the title. Nil for title matches and related items.
        let snippet: Snippet?
        let payload: Payload
    }

    struct ResultGroup<Payload>: Identifiable {
        let kind: GroupKind
        let rows: [Row<Payload>]

        var id: String { kind.rawValue }
    }

    /// Sorts search hits under the Library's headings.
    ///
    /// - `exact`: the fuzzy pass's item and reflection hits, best first.
    /// - `tagged`: one candidate per item and tag the search found, best tag
    ///   first, with the tag's name as `body`.
    /// - `related`: the semantic hits, best first.
    /// - `allowedItemIDs`: the items the Library is showing (board filter,
    ///   archived toggle). A hit on any other item is dropped. Nil allows all.
    ///
    /// An item hit goes under Titles when the query is in its title, and
    /// otherwise under the heading for its text with a snippet around the
    /// match. Reflections always carry a snippet and sit with the user's
    /// notes, the two merged best score first. An item carrying a tag whose
    /// name holds the query (as `titleContains` reads it; loose matches are
    /// left out) is listed under Tagged, once, with the matching tag names as
    /// its snippet. A tagged or related item already listed under an earlier
    /// heading is not repeated. Empty groups are left out.
    static func groups<Payload>(
        query: String,
        exact: [Candidate<Payload>],
        tagged: [Candidate<Payload>] = [],
        related: [Candidate<Payload>],
        allowedItemIDs: Set<UUID>? = nil
    ) -> [ResultGroup<Payload>] {
        func isAllowed(_ candidate: Candidate<Payload>) -> Bool {
            allowedItemIDs?.contains(candidate.itemID) ?? true
        }

        var titles: [Row<Payload>] = []
        var notes: [(row: Row<Payload>, score: Double, offset: Int)] = []
        var text: [Row<Payload>] = []
        var listedItemIDs = Set<UUID>()

        for (offset, candidate) in exact.enumerated() where isAllowed(candidate) {
            listedItemIDs.insert(candidate.itemID)

            switch placement(of: candidate, query: query) {
            case .title:
                titles.append(makeRow(for: candidate, line: nil))
            case .body(let line):
                let hit = makeRow(for: candidate, line: line)
                if candidate.source == .reflection || candidate.isNote {
                    notes.append((row: hit, score: candidate.score, offset: offset))
                } else {
                    text.append(hit)
                }
            }
        }

        // Notes and reflections arrive as two separately ranked lists.
        let rankedNotes = notes
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
            .map { $0.row }

        // One row per item, naming every matching tag it carries.
        var taggedOrder: [UUID] = []
        var taggedFirst: [UUID: Candidate<Payload>] = [:]
        var taggedNames: [UUID: [String]] = [:]
        for candidate in tagged where isAllowed(candidate) && titleContains(candidate.body, query: query) {
            guard !listedItemIDs.contains(candidate.itemID) else { continue }
            if taggedFirst[candidate.itemID] == nil {
                taggedOrder.append(candidate.itemID)
                taggedFirst[candidate.itemID] = candidate
            }
            var names = taggedNames[candidate.itemID] ?? []
            if !names.contains(candidate.body) {
                names.append(candidate.body)
            }
            taggedNames[candidate.itemID] = names
        }
        var taggedRows: [Row<Payload>] = []
        for itemID in taggedOrder {
            guard let first = taggedFirst[itemID] else { continue }
            let names = (taggedNames[itemID] ?? []).joined(separator: ", ")
            let line = snippet(in: names, matching: query, lead: names.count, trail: names.count)
            taggedRows.append(makeRow(for: first, line: line))
            listedItemIDs.insert(itemID)
        }

        var relatedRows: [Row<Payload>] = []
        for candidate in related where isAllowed(candidate) {
            guard listedItemIDs.insert(candidate.itemID).inserted else { continue }
            relatedRows.append(makeRow(for: candidate, line: nil))
        }

        let all: [(GroupKind, [Row<Payload>])] = [
            (.titles, titles),
            (.notes, rankedNotes),
            (.text, text),
            (.tagged, taggedRows),
            (.related, relatedRows),
        ]
        var result: [ResultGroup<Payload>] = []
        for (kind, rows) in all where !rows.isEmpty {
            result.append(ResultGroup(kind: kind, rows: rows))
        }
        return result
    }

    private enum Placement {
        case title
        case body(Snippet?)
    }

    private static func placement<Payload>(of candidate: Candidate<Payload>, query: String) -> Placement {
        if candidate.source == .reflection {
            return .body(snippet(inMarkdown: candidate.body, matching: query) ?? excerpt(ofMarkdown: candidate.body))
        }
        if titleContains(candidate.title, query: query) {
            return .title
        }
        if let found = snippet(inMarkdown: candidate.body, matching: query) {
            return .body(found)
        }
        // Neither holds the query as typed, so the fuzzy pass matched loosely
        // (letters in order). If it was the title it matched, or there is no
        // text to show, this is a title hit; otherwise show how the text opens.
        let titleScore = FuzzySearchScorer.score(
            normalizedQuery: normalized(query).lowercased(),
            in: candidate.title.lowercased()
        )
        if titleScore > 0 {
            return .title
        }
        guard let opening = excerpt(ofMarkdown: candidate.body) else { return .title }
        return .body(opening)
    }

    private static func makeRow<Payload>(for candidate: Candidate<Payload>, line: Snippet?) -> Row<Payload> {
        Row(
            id: candidate.id,
            itemID: candidate.itemID,
            source: candidate.source,
            snippet: line,
            payload: candidate.payload
        )
    }

    /// True when `title` holds the query as typed (any case), or holds every
    /// word of a query of several words.
    static func titleContains(_ title: String, query: String) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return false }
        if title.range(of: needle, options: .caseInsensitive) != nil {
            return true
        }
        let words = needle.split(whereSeparator: \.isWhitespace)
        guard words.count > 1 else { return false }
        return words.allSatisfy { title.range(of: String($0), options: .caseInsensitive) != nil }
    }

    // MARK: - Snippet

    /// One line of text around a match, in three parts so the view can set
    /// the match in a heavier weight. Whitespace runs are collapsed to single
    /// spaces, and an ellipsis marks an end that was cut in the middle of a
    /// line (an end that is the end of its line is whole, and carries none).
    struct Snippet: Equatable, Sendable {
        /// Up to the match, with a leading "…" when the line was cut before it.
        let before: String
        /// The matched words as they are written in the text. Empty for an
        /// `excerpt`, which shows how the text opens without marking anything.
        let match: String
        /// After the match, with a trailing "…" when the line was cut after it.
        let after: String

        var text: String { before + match + after }
    }

    static let ellipsis = "\u{2026}"

    /// A snippet around the first place `query` occurs in `text`, ignoring
    /// case. For a query of several words that do not occur together, the
    /// earliest occurrence of any one word is used. Nil when nothing occurs.
    ///
    /// `lead` and `trail` are the most characters kept either side of the
    /// match. The lead is kept short so that the match itself survives when
    /// the line is truncated at its tail. Context stays on the match's own
    /// line, and a cut never lands inside a word unless the word is longer
    /// than the allowance.
    static func snippet(
        in text: String,
        matching query: String,
        lead: Int = 32,
        trail: Int = 96
    ) -> Snippet? {
        let needle = normalized(query)
        guard !needle.isEmpty, !text.isEmpty,
              let match = matchRange(of: needle, in: text) else { return nil }

        let windowStart = text.index(match.lowerBound, offsetBy: -max(lead, 0), limitedBy: text.startIndex)
            ?? text.startIndex
        let windowEnd = text.index(match.upperBound, offsetBy: max(trail, 0), limitedBy: text.endIndex)
            ?? text.endIndex

        var start = windowStart
        var cutBefore = false
        let leadIn = text[windowStart..<match.lowerBound]
        if let lineBreak = leadIn.lastIndex(where: \.isNewline) {
            start = text.index(after: lineBreak)
        } else if windowStart > text.startIndex {
            let previous = text[text.index(before: windowStart)]
            if !previous.isNewline {
                cutBefore = true
                // The window opens inside a word: begin at the next whole one.
                if !previous.isWhitespace, let space = leadIn.firstIndex(where: \.isWhitespace) {
                    start = text.index(after: space)
                }
            }
        }

        var end = windowEnd
        var cutAfter = false
        let leadOut = text[match.upperBound..<windowEnd]
        if let lineBreak = leadOut.firstIndex(where: \.isNewline) {
            end = lineBreak
        } else if windowEnd < text.endIndex {
            let next = text[windowEnd]
            if !next.isNewline {
                cutAfter = true
                // The window closes inside a word: end at the last whole one.
                if !next.isWhitespace, let space = leadOut.lastIndex(where: \.isWhitespace) {
                    end = space
                }
            }
        }

        let before = collapsingWhitespace(text[start..<match.lowerBound], trimmingStart: true)
        let after = collapsingWhitespace(text[match.upperBound..<end], trimmingEnd: true)

        return Snippet(
            before: (cutBefore ? ellipsis : "") + before,
            match: collapsingWhitespace(text[match]),
            after: after + (cutAfter ? ellipsis : "")
        )
    }

    /// How `text` opens: its first line with anything on it, cut at a word
    /// boundary within `length` characters. Used when a hit has no literal
    /// match to centre on. Nil when the text is blank.
    static func excerpt(of text: String, length: Int = 128) -> Snippet? {
        guard let first = text.firstIndex(where: { !$0.isWhitespace }) else { return nil }
        let lineEnd = text[first...].firstIndex(where: \.isNewline) ?? text.endIndex
        var end = text.index(first, offsetBy: max(length, 1), limitedBy: lineEnd) ?? lineEnd
        let isCut = end < lineEnd
        if isCut, !text[end].isWhitespace,
           let space = text[first..<end].lastIndex(where: \.isWhitespace) {
            end = space
        }

        let opening = collapsingWhitespace(text[first..<end], trimmingEnd: true)
        return Snippet(before: opening + (isCut ? ellipsis : ""), match: "", after: "")
    }

    // MARK: - Markdown

    /// `snippet(in:matching:)` for stored text that may be Markdown: each
    /// line has its marks taken off (`plainLine`) before it is searched, so
    /// the snippet reads as prose and "**augment**" still matches "augment".
    /// The snippet keeps to its match's line, so lines are stripped one at a
    /// time and only as far as the first that matches.
    static func snippet(
        inMarkdown text: String,
        matching query: String,
        lead: Int = 32,
        trail: Int = 96
    ) -> Snippet? {
        let needle = normalized(query)
        guard !needle.isEmpty, !text.isEmpty else { return nil }

        var plainLines: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = plainLine(rawLine)
            if line.range(of: needle, options: .caseInsensitive) != nil {
                return snippet(in: line, matching: needle, lead: lead, trail: trail)
            }
            plainLines.append(line)
        }

        // No line holds the query as typed: the first line holding any one
        // of its words, as `snippet(in:matching:)` falls back.
        let words = needle.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return nil }
        for line in plainLines
        where words.contains(where: { line.range(of: $0, options: .caseInsensitive) != nil }) {
            return snippet(in: line, matching: needle, lead: lead, trail: trail)
        }
        return nil
    }

    /// `excerpt(of:)` for stored text that may be Markdown: the first line
    /// with a letter or digit left once its marks are off. Nil when there is
    /// none (blank text, or only dividers and fences).
    static func excerpt(ofMarkdown text: String, length: Int = 128) -> Snippet? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = plainLine(rawLine)
            guard line.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            return excerpt(of: line, length: length)
        }
        return nil
    }

    /// One line of Markdown as plain prose: heading hashes, quote, list and
    /// task prefixes, link and image syntax, wiki-link brackets (an alias
    /// wins over the target), and emphasis, code and strikethrough marks are
    /// removed; the words are left alone. A code fence's own line is blank.
    static func plainLine<S: StringProtocol>(_ line: S) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return "" }

        // Most lines of saved text carry no mark at all: every pattern below
        // needs one of these characters, or a line opening with "-", "+" or
        // a digit, so such a line is returned without running them.
        let marks: Set<Character> = ["#", ">", "*", "_", "`", "[", "~"]
        let opensLikeAList = trimmed.first.map { $0 == "-" || $0 == "+" || $0.isNumber } ?? false
        if !opensLikeAList, !trimmed.contains(where: { marks.contains($0) }) {
            return trimmed
        }

        var text = trimmed
        let replacements: [(pattern: String, template: String)] = [
            // Quote prefixes, nested or not.
            (#"^(>\s?)+"#, ""),
            // Heading, bullet (with or without a task box), numbered item.
            (#"^\s*(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)"#, ""),
            // [[Target|alias]] keeps its alias; [[Target]] its target.
            (#"\[\[([^\]|]+)\|([^\]]+)\]\]"#, "$2"),
            (#"\[\[(.+?)\]\]"#, "$1"),
            // [text](url) and ![alt](url) keep their text.
            (#"!?\[([^\]]*)\]\([^)]*\)"#, "$1"),
            // Emphasis, code and strikethrough marks.
            (#"[*`]|~~"#, ""),
            // Underscores that open or close emphasis, not ones inside a word.
            (#"(?<![\p{L}\p{N}])_+|_+(?![\p{L}\p{N}])"#, ""),
        ]
        for replacement in replacements {
            text = text.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.template,
                options: .regularExpression
            )
        }
        return text
    }

    // MARK: - Boards

    /// The boards offered as rows above the results: those whose name holds
    /// the query (as `titleContains` reads it), in the order given, without
    /// the board the list is already filtered to, each once.
    static func offeredBoards<Element>(
        _ boards: [Element],
        query: String,
        excluding currentID: UUID?,
        id: (Element) -> UUID,
        title: (Element) -> String
    ) -> [Element] {
        var seen = Set<UUID>()
        var offered: [Element] = []
        for board in boards {
            let boardID = id(board)
            guard boardID != currentID, titleContains(title(board), query: query) else { continue }
            if seen.insert(boardID).inserted {
                offered.append(board)
            }
        }
        return offered
    }

    // MARK: - Keyboard Highlight

    /// Where Down (`step` 1) or Up (`step` -1) moves the keyboard highlight
    /// through `rowIDs`, the rows in display order.
    ///
    /// Down from no highlight (or from a row no longer listed) lands on the
    /// first row; Up from there stays in the field, with no highlight. Up
    /// from the first row returns to the field; Down on the last row stays.
    static func movedHighlight(from current: String?, by step: Int, in rowIDs: [String]) -> String? {
        guard !rowIDs.isEmpty else { return nil }
        guard let current, let index = rowIDs.firstIndex(of: current) else {
            return step > 0 ? rowIDs.first : nil
        }
        let target = index + step
        guard target >= 0 else { return nil }
        return rowIDs[min(target, rowIDs.count - 1)]
    }

    // MARK: - Count

    /// "1 result", "6 results": the count shown inside the find field.
    static func countLabel(_ count: Int) -> String {
        count == 1 ? "1 result" : "\(count) results"
    }

    // MARK: - Helpers

    private static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchRange(of needle: String, in text: String) -> Range<String.Index>? {
        if let whole = text.range(of: needle, options: .caseInsensitive) {
            return whole
        }
        let words = needle.split(whereSeparator: \.isWhitespace)
        guard words.count > 1 else { return nil }
        return words
            .compactMap { text.range(of: String($0), options: .caseInsensitive) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    /// `text` with each run of whitespace (line breaks included) as one space.
    private static func collapsingWhitespace(
        _ text: Substring,
        trimmingStart: Bool = false,
        trimmingEnd: Bool = false
    ) -> String {
        var result = ""
        var pendingSpace = false
        for character in text {
            if character.isWhitespace {
                pendingSpace = true
            } else {
                if pendingSpace, !(trimmingStart && result.isEmpty) {
                    result.append(" ")
                }
                pendingSpace = false
                result.append(character)
            }
        }
        if pendingSpace, !trimmingEnd, !(trimmingStart && result.isEmpty) {
            result.append(" ")
        }
        return result
    }
}
