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
        /// Nothing matches literally; the embedding index places it nearby.
        case related

        var title: String {
            switch self {
            case .titles: "Titles"
            case .notes: "In your notes and reflections"
            case .text: "In the text"
            case .related: "Related in meaning"
            }
        }
    }

    /// Where a hit came from in `SearchViewModel`'s results.
    enum Source: Sendable {
        case item
        case reflection
    }

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
        /// item's note body / saved text. Empty when there is none.
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

    struct Group<Payload>: Identifiable {
        let kind: GroupKind
        let rows: [Row<Payload>]

        var id: String { kind.rawValue }
    }

    /// Sorts search hits under the Library's headings.
    ///
    /// - `exact`: the fuzzy pass's item and reflection hits, best first.
    /// - `related`: the semantic hits, best first.
    /// - `allowedItemIDs`: the items the Library is showing (board filter,
    ///   archived toggle). A hit on any other item is dropped. Nil allows all.
    ///
    /// An item hit goes under Titles when the query is in its title, and
    /// otherwise under the heading for its text with a snippet around the
    /// match. Reflections always carry a snippet and sit with the user's
    /// notes, the two merged best score first. A related item already listed
    /// under another heading is not repeated. Empty groups are left out.
    static func groups<Payload>(
        query: String,
        exact: [Candidate<Payload>],
        related: [Candidate<Payload>],
        allowedItemIDs: Set<UUID>? = nil
    ) -> [Group<Payload>] {
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

        var relatedRows: [Row<Payload>] = []
        for candidate in related where isAllowed(candidate) {
            guard listedItemIDs.insert(candidate.itemID).inserted else { continue }
            relatedRows.append(makeRow(for: candidate, line: nil))
        }

        let all: [(GroupKind, [Row<Payload>])] = [
            (.titles, titles),
            (.notes, rankedNotes),
            (.text, text),
            (.related, relatedRows),
        ]
        return all.compactMap { kind, rows in
            rows.isEmpty ? nil : Group(kind: kind, rows: rows)
        }
    }

    private enum Placement {
        case title
        case body(Snippet?)
    }

    private static func placement<Payload>(of candidate: Candidate<Payload>, query: String) -> Placement {
        if candidate.source == .reflection {
            return .body(snippet(in: candidate.body, matching: query) ?? excerpt(of: candidate.body))
        }
        if titleContains(candidate.title, query: query) {
            return .title
        }
        if let found = snippet(in: candidate.body, matching: query) {
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
        guard let opening = excerpt(of: candidate.body) else { return .title }
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
    /// spaces, and an ellipsis marks each end that is not the end of the text.
    struct Snippet: Equatable, Sendable {
        /// Up to the match, with a leading "…" when text was left out before it.
        let before: String
        /// The matched words as they are written in the text. Empty for an
        /// `excerpt`, which shows how the text opens without marking anything.
        let match: String
        /// After the match, with a trailing "…" when text was left out after it.
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

        var start = text.index(match.lowerBound, offsetBy: -max(lead, 0), limitedBy: text.startIndex)
            ?? text.startIndex
        var end = text.index(match.upperBound, offsetBy: max(trail, 0), limitedBy: text.endIndex)
            ?? text.endIndex

        let leadIn = text[start..<match.lowerBound]
        if let lineBreak = leadIn.lastIndex(where: \.isNewline) {
            start = text.index(after: lineBreak)
        } else if start > text.startIndex, let space = leadIn.firstIndex(where: \.isWhitespace) {
            start = text.index(after: space)
        }

        let leadOut = text[match.upperBound..<end]
        if let lineBreak = leadOut.firstIndex(where: \.isNewline) {
            end = lineBreak
        } else if end < text.endIndex, let space = leadOut.lastIndex(where: \.isWhitespace) {
            end = space
        }

        let textBefore = text[..<start].contains { !$0.isWhitespace }
        let textAfter = text[end...].contains { !$0.isWhitespace }

        let before = collapsingWhitespace(text[start..<match.lowerBound], trimmingStart: true)
        let after = collapsingWhitespace(text[match.upperBound..<end], trimmingEnd: true)

        return Snippet(
            before: (textBefore ? ellipsis : "") + before,
            match: collapsingWhitespace(text[match]),
            after: after + (textAfter ? ellipsis : "")
        )
    }

    /// How `text` opens: its first line with anything on it, cut at a word
    /// boundary within `length` characters. Used when a hit has no literal
    /// match to centre on. Nil when the text is blank.
    static func excerpt(of text: String, length: Int = 128) -> Snippet? {
        guard let first = text.firstIndex(where: { !$0.isWhitespace }) else { return nil }
        let lineEnd = text[first...].firstIndex(where: \.isNewline) ?? text.endIndex
        var end = text.index(first, offsetBy: max(length, 1), limitedBy: lineEnd) ?? lineEnd
        if end < lineEnd, let space = text[first..<end].lastIndex(where: \.isWhitespace) {
            end = space
        }

        let textAfter = text[end...].contains { !$0.isWhitespace }
        let opening = collapsingWhitespace(text[first..<end], trimmingEnd: true)
        return Snippet(before: opening + (textAfter ? ellipsis : ""), match: "", after: "")
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
