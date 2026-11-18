import Foundation

/// What Today shows around the inbox, worked out from the library alone: the
/// day's masthead, "Earlier today", and the notes under "Continue".
///
/// Pure functions over an item's dates, type and status, with the clock and
/// calendar passed in, so each rule can be tested without a view.
enum TodayDigest {
    /// Rows in "Earlier today".
    static let earlierLimit = 6
    /// Notes under "Continue".
    static let continueLimit = 3
    /// The longest a snippet runs, in characters, before it is cut short.
    static let snippetLimit = 140

    // MARK: - Masthead

    /// The day as the page's title: weekday, day and month in the reader's
    /// own order ("Tuesday, 17 November" / "Tuesday, November 17").
    static func mastheadTitle(
        for date: Date,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide)
            .day()
            .month(.wide)
        return date.formatted(style)
    }

    // MARK: - Earlier today

    /// What happened to an item today, as far as its dates and type can say.
    /// Nothing here claims more than that: an item's `updatedAt` moves for a
    /// keep, a tag, a highlight or a board, and the model does not record
    /// which, so anything older than today is only ever "Updated".
    enum Touch: Equatable, Sendable {
        /// A note created today.
        case noteWritten
        /// A note from an earlier day, changed today.
        case noteEdited
        /// A source captured today that is now in the library.
        case saved
        /// A source from an earlier day, changed today.
        case updated

        var label: String {
            switch self {
            case .noteWritten: "Note written"
            case .noteEdited: "Note edited"
            case .saved: "Saved"
            case .updated: "Updated"
            }
        }
    }

    /// One row of "Earlier today".
    struct EarlierEntry: Identifiable {
        let item: Item
        /// When the item was last touched: the later of created and updated.
        let touchedAt: Date
        let touch: Touch

        var id: UUID { item.id }
    }

    /// Library items touched today, newest first.
    ///
    /// Only `.active` items qualify. The inbox has its own section, and what
    /// was dropped, archived or set aside for later has been put away: it
    /// does not come back on Today.
    static func earlierToday(
        from items: [Item],
        now: Date = .now,
        calendar: Calendar = .current,
        limit: Int = earlierLimit
    ) -> [EarlierEntry] {
        let entries = items.compactMap { item -> EarlierEntry? in
            guard item.status == .active else { return nil }
            let touchedAt = max(item.createdAt, item.updatedAt)
            guard calendar.isDate(touchedAt, inSameDayAs: now) else { return nil }
            return EarlierEntry(
                item: item,
                touchedAt: touchedAt,
                touch: touch(for: item, now: now, calendar: calendar)
            )
        }
        return Array(entries.sorted { $0.touchedAt > $1.touchedAt }.prefix(max(0, limit)))
    }

    static func touch(for item: Item, now: Date = .now, calendar: Calendar = .current) -> Touch {
        let createdToday = calendar.isDate(item.createdAt, inSameDayAs: now)
        if item.type == .note {
            return createdToday ? .noteWritten : .noteEdited
        }
        return createdToday ? .saved : .updated
    }

    // MARK: - Continue

    /// The notes most recently worked on: kept notes only, newest edit first.
    static func continueNotes(from items: [Item], limit: Int = continueLimit) -> [Item] {
        let notes = items.filter { $0.type == .note && $0.status == .active }
        return Array(notes.sorted { $0.updatedAt > $1.updatedAt }.prefix(max(0, limit)))
    }

    /// The first line of a note that says something, with its Markdown marks
    /// taken off. Nil for a note with no words in it.
    static func snippet(from content: String?, limit: Int = snippetLimit) -> String? {
        guard let content else { return nil }
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            // A code fence's own line ("```swift") names a language, not a thought.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { continue }
            let line = plainText(trimmed)
            // Dividers and stray markers have no letters or digits left.
            guard line.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            guard line.count > limit else { return line }
            return String(line.prefix(limit)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
        }
        return nil
    }

    /// Words in a note, counted the way the editor's own folio line counts
    /// them: runs of anything between whitespace.
    static func wordCount(of content: String?) -> Int {
        guard let content else { return 0 }
        return content.split(whereSeparator: \.isWhitespace).count
    }

    /// "108 words", "1 word", or nil for an empty note.
    static func wordCountLabel(for content: String?) -> String? {
        let count = wordCount(of: content)
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? "word" : "words")"
    }

    // MARK: - Markdown

    /// One line of Markdown as plain prose: block markers, link syntax and
    /// emphasis marks removed, the words left alone.
    private static func plainText(_ line: String) -> String {
        var text = line
        let replacements: [(pattern: String, template: String)] = [
            // Heading, quote, bullet (with or without a task box), numbered item.
            (#"^(#{1,6}\s+|>\s*|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)"#, ""),
            // [[Wiki link]] keeps its title.
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
        return text.trimmingCharacters(in: .whitespaces)
    }
}
