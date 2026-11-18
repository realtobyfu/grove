import Foundation

/// The editing rules for nested lists, kept apart from the text view so they
/// can be tested: what Tab and Shift-Tab do to list lines, and what Return
/// does at the end of one.
///
/// One level of nesting is two spaces of indentation, which is also how the
/// parser and the rendered views read it (`MarkdownTypeSpec.nestingLevel`).
enum MarkdownListEditing {
    /// Spaces per nesting level.
    static let indentUnit = "  "
    /// Deepest level Tab will nest to.
    static let maxLevel = MarkdownTypeSpec.maxNestingLevel

    // MARK: - Reading a line

    struct ListLine: Equatable {
        enum Kind: Equatable {
            case bullet(marker: Character)
            case task(marker: Character)
            case ordered(number: Int, delimiter: Character)
        }

        /// Leading spaces and tabs.
        let indent: String
        let kind: Kind
        /// The whitespace between the marker and the content.
        let spacer: String
        /// What follows the marker (and the task box), untrimmed.
        let content: String

        var level: Int {
            MarkdownTypeSpec.nestingLevel(forIndentation: indent.count)
        }
    }

    /// The line as a list item, or nil when it is not one.
    static func listLine(_ line: String) -> ListLine? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        var rest = Substring(line.dropFirst(indent.count))

        // The same markers the parser reads. A marker needs a space after it,
        // so "-" alone, "---" and "*emphasis*" are not items.
        if let first = rest.first, first == "-" || first == "*" {
            rest = rest.dropFirst()
            let spacer = String(rest.prefix { $0 == " " || $0 == "\t" })
            guard !spacer.isEmpty else { return nil }
            rest = rest.dropFirst(spacer.count)
            for box in ["[ ]", "[x]", "[X]"] where rest == box || rest.hasPrefix(box + " ") {
                let content = rest.dropFirst(box.count).drop { $0 == " " }
                return ListLine(indent: indent, kind: .task(marker: first), spacer: spacer, content: String(content))
            }
            return ListLine(indent: indent, kind: .bullet(marker: first), spacer: spacer, content: String(rest))
        }

        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9, let number = Int(digits) else { return nil }
        rest = rest.dropFirst(digits.count)
        guard let delimiter = rest.first, delimiter == "." || delimiter == ")" else { return nil }
        rest = rest.dropFirst()
        let spacer = String(rest.prefix { $0 == " " || $0 == "\t" })
        guard !spacer.isEmpty else { return nil }
        rest = rest.dropFirst(spacer.count)
        return ListLine(indent: indent, kind: .ordered(number: number, delimiter: delimiter), spacer: spacer, content: String(rest))
    }

    // MARK: - Tab and Shift-Tab

    /// The lines with every list line among them nested one level deeper
    /// (`outward: false`) or brought one level out (`outward: true`). Other
    /// lines are left alone. Returns nil when nothing would change — no list
    /// line, or every list line already at the limit — so Tab can keep its
    /// usual meaning there.
    ///
    /// `deltas` is the change in length of each line, for moving the caret.
    /// A numbered item nested deeper starts its new level at 1.
    static func shifted(_ lines: [String], outward: Bool) -> (lines: [String], deltas: [Int])? {
        var result = lines
        var deltas = Array(repeating: 0, count: lines.count)
        var changed = false

        for index in lines.indices {
            guard let item = listLine(lines[index]) else { continue }
            let line = lines[index]
            if outward {
                let removable: Int
                if item.indent.hasPrefix("\t") {
                    removable = 1
                } else {
                    removable = min(indentUnit.count, item.indent.prefix { $0 == " " }.count)
                }
                guard removable > 0 else { continue }
                result[index] = String(line.dropFirst(removable))
                deltas[index] = -removable
                changed = true
            } else {
                guard item.level < maxLevel else { continue }
                var body = String(line.dropFirst(item.indent.count))
                if case .ordered(let number, let delimiter) = item.kind, number != 1 {
                    let oldMarker = "\(number)\(delimiter)"
                    body = "1\(delimiter)" + body.dropFirst(oldMarker.count)
                }
                let nested = item.indent + indentUnit + body
                deltas[index] = nested.count - line.count
                result[index] = nested
                changed = true
            }
        }

        return changed ? (result, deltas) : nil
    }

    // MARK: - Return

    enum ReturnAction: Equatable {
        /// Not a list line: Return does what it always does.
        case notAList
        /// An empty nested item: bring it one level out instead of ending
        /// the list. The string is the line's new text.
        case outdent(String)
        /// An empty top-level item: the marker goes and the line is left
        /// plain, which ends the list.
        case endList
        /// Start the next item with this prefix, at the same depth.
        case continueWith(String)
    }

    /// What Return does with the caret at the end of `line`.
    static func returnAction(for line: String) -> ReturnAction {
        guard let item = listLine(line) else { return .notAList }

        if item.content.trimmingCharacters(in: .whitespaces).isEmpty {
            if let shifted = shifted([line], outward: true) {
                return .outdent(shifted.lines[0])
            }
            return .endList
        }

        switch item.kind {
        case .bullet(let marker):
            return .continueWith("\(item.indent)\(marker)\(item.spacer)")
        case .task(let marker):
            return .continueWith("\(item.indent)\(marker)\(item.spacer)[ ] ")
        case .ordered(let number, let delimiter):
            return .continueWith("\(item.indent)\(number + 1)\(delimiter)\(item.spacer)")
        }
    }
}
