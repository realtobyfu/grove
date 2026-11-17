import Foundation

/// A board read as a trail: its items in the user's own order, with the
/// sources numbered as stops along the way and the user's notes left in
/// place between them.
///
/// This is the logic behind `BoardTrailView`, kept free of SwiftUI so it can
/// be tested. It does not resolve the order itself: hand it items that are
/// already in the board's manual order.
struct BoardTrail {
    enum Entry: Identifiable {
        /// Anything that is not a note. `number` counts sources only, from 1.
        case source(number: Int, item: Item)
        /// One of the user's own notes. Notes take no number.
        case note(Item)

        var item: Item {
            switch self {
            case .source(_, let item): return item
            case .note(let item): return item
            }
        }

        var id: UUID { item.id }

        var isSource: Bool {
            switch self {
            case .source: return true
            case .note: return false
            }
        }
    }

    let entries: [Entry]
    let sourceCount: Int
    let noteCount: Int

    /// - Parameter orderedItems: the board's active items, already in the
    ///   order the trail should follow.
    init(orderedItems: [Item]) {
        var entries: [Entry] = []
        entries.reserveCapacity(orderedItems.count)
        var sourceCount = 0
        var noteCount = 0

        for item in orderedItems {
            if item.type == .note {
                noteCount += 1
                entries.append(.note(item))
            } else {
                sourceCount += 1
                entries.append(.source(number: sourceCount, item: item))
            }
        }

        self.entries = entries
        self.sourceCount = sourceCount
        self.noteCount = noteCount
    }

    // MARK: - Masthead

    /// "4 sources · 2 notes". A kind with nothing in it is left out, so a
    /// board of sources alone reads "4 sources"; an empty trail is "".
    var countsLine: String {
        Self.countsLine(sources: sourceCount, notes: noteCount)
    }

    static func countsLine(sources: Int, notes: Int) -> String {
        var parts: [String] = []
        if sources > 0 {
            parts.append("\(sources) \(sources == 1 ? "source" : "sources")")
        }
        if notes > 0 {
            parts.append("\(notes) \(notes == 1 ? "note" : "notes")")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// A board's description as the masthead shows it: trimmed, and nil when
    /// there is nothing to show.
    static func descriptionText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Source rows

    /// The short word a source row sets in its type column.
    static func typeLabel(for item: Item) -> String {
        switch item.type {
        case .article: return item.isPDFDocument ? "PDF" : "Article"
        case .video: return "Video"
        case .codebase: return "Code"
        case .courseLecture: return "Lecture"
        case .note: return "Note"
        }
    }

    /// What a source row sets at its trailing edge: where the source lives,
    /// and how long it runs when that is known ("youtube.com · 1:40:00").
    static func sourceMeta(for item: Item) -> String? {
        var parts: [String] = []
        if let domain = sourceDomain(for: item) {
            parts.append(domain)
        }
        if let duration = item.videoDurationLabel {
            parts.append(duration)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// The web domain a source came from. Nil for anything that is not a web
    /// address (a file imported from disk has a path, not a domain).
    static func sourceDomain(for item: Item) -> String? {
        guard !item.isVideoLocalFile,
              let raw = item.sourceURL,
              let url = resolvedSourceURL(from: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return domainFrom(raw)
    }

    // MARK: - Inline notes

    /// How many lines of a note the trail shows before handing over to
    /// "Continue writing". Also the per-paragraph line limit in the view.
    static let noteExcerptLineLimit = 6

    /// Roughly how many characters of note text fit on one line of the trail
    /// column. Only used to estimate how many lines a paragraph will take.
    static let noteExcerptCharactersPerLine = 90

    /// The opening of a note's Markdown, cut at a line boundary once it would
    /// run past `maxLines` displayed lines.
    ///
    /// Whole source lines are kept so Markdown is never cut mid-construct; a
    /// code fence left open by the cut is closed. The first line is always
    /// kept, however long it is: the view's line limit clips that one.
    static func noteExcerpt(
        of content: String?,
        maxLines: Int = noteExcerptLineLimit,
        charactersPerLine: Int = noteExcerptCharactersPerLine
    ) -> String {
        let trimmed = (content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let budget = max(1, maxLines)
        let width = max(1, charactersPerLine)

        var kept: [Substring] = []
        var usedLines = 0
        var isInsideFence = false
        var isTruncated = false

        for line in trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let isBlank = line.allSatisfy(\.isWhitespace)
            // A blank line between blocks takes no room of its own (the
            // renderer spaces blocks itself); inside a code block it does.
            let cost = (isBlank && !isInsideFence) ? 0 : max(1, (line.count + width - 1) / width)

            if usedLines > 0 && usedLines + cost > budget {
                isTruncated = true
                break
            }

            kept.append(line)
            usedLines += cost
            if line.hasPrefix("```") {
                isInsideFence.toggle()
            }
        }

        guard isTruncated else { return trimmed }

        if isInsideFence {
            if kept.count > 1, let last = kept.last, last.hasPrefix("```") {
                // The cut fell right after an opening fence: drop the fence
                // rather than show an empty code block.
                kept.removeLast()
            } else {
                kept.append("```")
            }
        }
        while let last = kept.last, last.allSatisfy(\.isWhitespace) {
            kept.removeLast()
        }
        return kept.joined(separator: "\n")
    }
}
