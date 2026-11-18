import Foundation

/// What the caret is in the middle of typing that the editor can help finish:
/// a `[[wiki link` or a `/block` command. Detected from the text alone so the
/// AppKit editor, the popup and the tests all agree on it.
enum EditorAssistTrigger: Equatable, Sendable {
    case wikiLink(query: String)
    case slash(query: String)

    var isSlash: Bool {
        if case .slash = self { return true }
        return false
    }

    /// - Parameter linePrefix: the caret's line, from its start up to the caret.
    /// - Returns: the trigger and the UTF-16 length of the token (`[[que` or
    ///   `/que`) counted back from the caret — the text a pick replaces.
    static func detect(linePrefix: String) -> (trigger: EditorAssistTrigger, tokenLength: Int)? {
        let prefix = linePrefix as NSString

        let open = prefix.range(of: "[[", options: .backwards)
        if open.location != NSNotFound {
            let query = prefix.substring(from: NSMaxRange(open))
            if !query.contains("]]") {
                return (.wikiLink(query: query), prefix.length - open.location)
            }
        }

        // A slash only opens the block menu at the start of a line, so
        // "and/or", dates and URLs never trigger it.
        let slash = prefix.range(of: "/", options: .backwards)
        if slash.location != NSNotFound {
            let before = prefix.substring(to: slash.location)
            let query = prefix.substring(from: NSMaxRange(slash))
            if before.allSatisfy({ $0 == " " || $0 == "\t" }),
               !query.contains(where: \.isWhitespace) {
                return (.slash(query: query), prefix.length - slash.location)
            }
        }

        return nil
    }
}

/// Keys the editor hands to an open assist popup instead of the text.
enum EditorAssistKey: Sendable {
    case up
    case down
    case commit
    case cancel
}

/// A block the `/` menu can start. Each one is plain markdown typed for you:
/// the menu is a way to find the syntax, not a second document model.
struct EditorBlockCommand: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// The markdown it stands for, shown in mono beside the title.
    let hint: String
    let keywords: [String]
    /// Replaces the typed `/query`.
    let insertion: String
    /// Where the caret lands, counted back from the end of the insertion.
    var cursorOffset: Int = 0

    static let all: [EditorBlockCommand] = [
        EditorBlockCommand(id: "h1", title: "Title", hint: "#", keywords: ["h1", "heading", "title"], insertion: "# "),
        EditorBlockCommand(id: "h2", title: "Heading", hint: "##", keywords: ["h2", "heading"], insertion: "## "),
        EditorBlockCommand(id: "h3", title: "Subheading", hint: "###", keywords: ["h3", "heading", "subheading"], insertion: "### "),
        EditorBlockCommand(id: "list", title: "List", hint: "-", keywords: ["bullet", "list", "ul"], insertion: "- "),
        EditorBlockCommand(id: "numbered", title: "Numbered list", hint: "1.", keywords: ["numbered", "ordered", "ol", "list"], insertion: "1. "),
        EditorBlockCommand(id: "task", title: "Task", hint: "- [ ]", keywords: ["task", "todo", "checkbox", "check"], insertion: "- [ ] "),
        EditorBlockCommand(id: "quote", title: "Quote", hint: ">", keywords: ["quote", "blockquote"], insertion: "> "),
        EditorBlockCommand(id: "code", title: "Code block", hint: "```", keywords: ["code", "fence", "snippet"], insertion: "```\n\n```", cursorOffset: -4),
        EditorBlockCommand(id: "divider", title: "Divider", hint: "---", keywords: ["divider", "rule", "hr", "line", "break"], insertion: "---\n"),
        EditorBlockCommand(id: "link", title: "Link to an item", hint: "[[", keywords: ["link", "wiki", "reference", "item"], insertion: "[["),
    ]

    /// Commands for a typed query: title or keyword prefix matches first, in
    /// menu order, then anything that merely contains the query.
    static func matching(_ query: String) -> [EditorBlockCommand] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return all }

        let prefixed = all.filter { command in
            command.title.lowercased().hasPrefix(needle) || command.keywords.contains { $0.hasPrefix(needle) }
        }
        let contained = all.filter { command in
            !prefixed.contains(command) && command.title.lowercased().contains(needle)
        }
        return prefixed + contained
    }
}
