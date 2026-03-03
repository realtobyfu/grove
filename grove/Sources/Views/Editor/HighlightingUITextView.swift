#if os(iOS)
import UIKit

// MARK: - Custom Attributed String Keys

extension NSAttributedString.Key {
    static let groveListPrefix = NSAttributedString.Key("groveListPrefix")
    static let groveQuotePrefix = NSAttributedString.Key("groveQuotePrefix")
}

// MARK: - MarkdownFormattingDelegate

protocol MarkdownFormattingDelegate: AnyObject {
    func wrapSelection(prefix: String, suffix: String)
    func insertPrefix(_ prefix: String)
    func insertText(_ text: String, cursorOffset: Int)
}

// MARK: - HighlightingUITextView

/// Custom UITextView subclass that handles formatting keyboard shortcuts
/// and draws custom bullet circles and quote rails for markdown.
/// iOS counterpart of macOS `HighlightingTextView` (NSTextView subclass).
class HighlightingUITextView: UITextView {
    static weak var focusedEditor: HighlightingUITextView?
    var showsMarkdownDecorations = false

    // MARK: - First Responder Tracking

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            Self.focusedEditor = self
        }
        return accepted
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        if Self.focusedEditor === self {
            Self.focusedEditor = nil
        }
        return super.resignFirstResponder()
    }

    // MARK: - Keyboard Shortcuts

    override var keyCommands: [UIKeyCommand]? {
        [
            shortcut("b", modifiers: .command, action: #selector(toggleBold), title: "Bold"),
            shortcut("i", modifiers: .command, action: #selector(toggleItalic), title: "Italic"),
            shortcut("e", modifiers: .command, action: #selector(toggleCode), title: "Inline Code"),
            shortcut("k", modifiers: .command, action: #selector(insertLink), title: "Link"),
            shortcut("k", modifiers: [.command, .shift], action: #selector(insertWikiLink), title: "Wiki Link"),
            shortcut("l", modifiers: [.command, .shift], action: #selector(insertList), title: "List"),
            shortcut("q", modifiers: [.command, .shift], action: #selector(insertQuote), title: "Quote"),
            shortcut("x", modifiers: [.command, .shift], action: #selector(toggleStrikethrough), title: "Strikethrough"),
        ]
    }

    private func shortcut(_ input: String, modifiers: UIKeyModifierFlags, action: Selector, title: String) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: action)
        command.discoverabilityTitle = title
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    @objc private func toggleBold() {
        wrapSelectionWith(prefix: "**", suffix: "**")
    }

    override func toggleBoldface(_ sender: Any?) {
        toggleBold()
    }

    @objc private func toggleItalic() {
        wrapSelectionWith(prefix: "*", suffix: "*")
    }

    override func toggleItalics(_ sender: Any?) {
        toggleItalic()
    }

    @objc private func toggleCode() {
        wrapSelectionWith(prefix: "`", suffix: "`")
    }

    @objc private func insertLink() {
        wrapSelectionWith(prefix: "[", suffix: "](url)")
    }

    @objc private func insertWikiLink() {
        insertTextAtSelection("[[]]", cursorOffset: -2)
    }

    @objc private func insertList() {
        toggleLinePrefix("- ")
    }

    @objc private func insertQuote() {
        toggleLinePrefix("> ")
    }

    @objc private func toggleStrikethrough() {
        wrapSelectionWith(prefix: "~~", suffix: "~~")
    }

    // MARK: - Text Manipulation

    func wrapSelectionWith(prefix: String, suffix: String) {
        let storage = textStorage
        let sel = selectedRange
        let prefixLength = utf16Length(of: prefix)
        let suffixLength = utf16Length(of: suffix)

        if sel.length == 0 {
            let insertion = prefix + suffix
            storage.replaceCharacters(in: sel, with: insertion)
            selectedRange = NSRange(location: sel.location + prefixLength, length: 0)
            delegate?.textViewDidChange?(self)
            return
        }

        let nsText = storage.string as NSString
        let selectedText = nsText.substring(with: sel)
        let segments = splitOuterWhitespace(selectedText)

        // Toggle off: if already wrapped, unwrap
        if !segments.core.isEmpty,
           segments.core.hasPrefix(prefix),
           segments.core.hasSuffix(suffix),
           utf16Length(of: segments.core) >= prefixLength + suffixLength {
            let coreText = segments.core as NSString
            let innerRange = NSRange(
                location: prefixLength,
                length: coreText.length - prefixLength - suffixLength
            )
            let inner = coreText.substring(with: innerRange)
            let replacement = segments.leading + inner + segments.trailing

            textStorage.replaceCharacters(in: sel, with: replacement)
            let newStart = sel.location + utf16Length(of: segments.leading)
            selectedRange = NSRange(location: newStart, length: utf16Length(of: inner))
            delegate?.textViewDidChange?(self)
            return
        }

        let replacement: String
        let selectionStart: Int
        let selectionLength: Int

        if segments.core.isEmpty {
            replacement = prefix + selectedText + suffix
            selectionStart = sel.location + prefixLength
            selectionLength = sel.length
        } else {
            replacement = segments.leading + prefix + segments.core + suffix + segments.trailing
            selectionStart = sel.location + utf16Length(of: segments.leading) + prefixLength
            selectionLength = utf16Length(of: segments.core)
        }

        textStorage.replaceCharacters(in: sel, with: replacement)
        selectedRange = NSRange(location: selectionStart, length: selectionLength)
        delegate?.textViewDidChange?(self)
    }

    func insertPrefixAtCurrentLine(_ prefix: String) {
        let sel = selectedRange
        let nsText = textStorage.string as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: sel.location, length: 0))
        let insertionRange = NSRange(location: lineRange.location, length: 0)
        let prefixLength = (prefix as NSString).length

        self.textStorage.replaceCharacters(in: insertionRange, with: prefix)
        selectedRange = NSRange(location: sel.location + prefixLength, length: sel.length)
        delegate?.textViewDidChange?(self)
    }

    func insertTextAtSelection(_ insertion: String, cursorOffset: Int = 0) {
        let sel = selectedRange
        let insertedLength = (insertion as NSString).length

        textStorage.replaceCharacters(in: sel, with: insertion)
        let minCursor = sel.location
        let maxCursor = sel.location + insertedLength
        let proposed = maxCursor + cursorOffset
        let clamped = min(max(proposed, minCursor), maxCursor)
        selectedRange = NSRange(location: clamped, length: 0)
        delegate?.textViewDidChange?(self)
    }

    func replaceActiveWikiQuery(with title: String) {
        guard selectedRange.length == 0 else { return }

        let nsText = textStorage.string as NSString
        let safeCursor = min(selectedRange.location, nsText.length)
        let prefix = nsText.substring(to: safeCursor)
        let prefixNSString = prefix as NSString
        let openRange = prefixNSString.range(of: "[[", options: .backwards)
        guard openRange.location != NSNotFound else { return }

        let queryStart = openRange.location + openRange.length
        let query = prefixNSString.substring(from: queryStart)
        guard !query.contains("]]"), !query.contains("\n") else { return }

        let replacementRange = NSRange(location: openRange.location, length: safeCursor - openRange.location)
        let replacement = "[[\(title)]]"
        let replacementLength = (replacement as NSString).length

        textStorage.replaceCharacters(in: replacementRange, with: replacement)
        let cursor = replacementRange.location + replacementLength
        selectedRange = NSRange(location: cursor, length: 0)
        delegate?.textViewDidChange?(self)
    }

    func toggleLinePrefix(_ prefix: String) {
        let sel = selectedRange
        let nsText = textStorage.string as NSString
        let lineBlockRange = selectedLineBlockRange(in: nsText, selection: sel)
        let lines = nsText.substring(with: lineBlockRange).components(separatedBy: "\n")
        let nonEmptyLines = lines.filter { !$0.isEmpty }
        let shouldRemovePrefix = !nonEmptyLines.isEmpty && nonEmptyLines.allSatisfy { $0.hasPrefix(prefix) }

        let transformed = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            if shouldRemovePrefix {
                return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
            }
            return prefix + line
        }

        let replacement = transformed.joined(separator: "\n")
        textStorage.replaceCharacters(in: lineBlockRange, with: replacement)

        if sel.length == 0 {
            let location = min(
                lineBlockRange.location + (shouldRemovePrefix ? 0 : utf16Length(of: prefix)),
                lineBlockRange.location + utf16Length(of: replacement)
            )
            selectedRange = NSRange(location: location, length: 0)
        } else {
            selectedRange = NSRange(location: lineBlockRange.location, length: utf16Length(of: replacement))
        }

        delegate?.textViewDidChange?(self)
    }

    func setHeadingLevel(_ level: Int) {
        let clampedLevel = min(max(level, 0), 6)
        let prefix = clampedLevel > 0 ? String(repeating: "#", count: clampedLevel) + " " : ""
        let sel = selectedRange
        let nsText = textStorage.string as NSString
        let lineBlockRange = selectedLineBlockRange(in: nsText, selection: sel)
        let lines = nsText.substring(with: lineBlockRange).components(separatedBy: "\n")

        let transformed = lines.map { line -> String in
            guard !line.isEmpty else { return line }
            return prefix + lineRemovingHeadingPrefix(line)
        }

        let replacement = transformed.joined(separator: "\n")
        textStorage.replaceCharacters(in: lineBlockRange, with: replacement)

        if sel.length == 0 {
            let location = min(
                lineBlockRange.location + utf16Length(of: prefix),
                lineBlockRange.location + utf16Length(of: replacement)
            )
            selectedRange = NSRange(location: location, length: 0)
        } else {
            selectedRange = NSRange(location: lineBlockRange.location, length: utf16Length(of: replacement))
        }

        delegate?.textViewDidChange?(self)
    }

    // MARK: - Custom Drawing

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard showsMarkdownDecorations else { return }
        drawMarkdownListBullets(in: rect)
        drawMarkdownQuoteRails(in: rect)
    }

    private func drawMarkdownListBullets(in dirtyRect: CGRect) {
        let lm = layoutManager
        let storage = textStorage
        let container = textContainer

        let selection = selectedRange
        let textOrigin = CGPoint(x: textContainerInset.left, y: textContainerInset.top)
        let markerColor = UIColor.secondaryLabel.withAlphaComponent(0.9)
        let baseSize = font?.pointSize ?? 16
        let bulletSize: CGFloat = baseSize >= 17 ? 5.4 : 4.6
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.enumerateAttribute(.groveListPrefix, in: fullRange, options: []) { value, range, _ in
            guard let isListPrefix = value as? Bool, isListPrefix, range.length > 0 else { return }

            if selection.length > 0, NSIntersectionRange(selection, range).length > 0 { return }
            if selection.length == 0 {
                let cursor = selection.location
                if cursor >= range.location && cursor < range.location + range.length { return }
            }

            let markerCharRange = NSRange(location: range.location, length: 1)
            let glyphRange = lm.glyphRange(forCharacterRange: markerCharRange, actualCharacterRange: nil)
            guard glyphRange.length > 0, glyphRange.location != NSNotFound else { return }

            var glyphRect = lm.boundingRect(forGlyphRange: glyphRange, in: container)
            glyphRect.origin.x += textOrigin.x
            glyphRect.origin.y += textOrigin.y
            guard glyphRect.intersects(dirtyRect) else { return }

            let bulletRect = CGRect(
                x: glyphRect.midX - bulletSize / 2,
                y: glyphRect.midY - bulletSize / 2 + 0.4,
                width: bulletSize,
                height: bulletSize
            )

            markerColor.setFill()
            UIBezierPath(ovalIn: bulletRect).fill()
        }
    }

    private func drawMarkdownQuoteRails(in dirtyRect: CGRect) {
        let lm = layoutManager
        let storage = textStorage
        let container = textContainer

        let nsText = storage.string as NSString
        let selection = selectedRange
        let textOrigin = CGPoint(x: textContainerInset.left, y: textContainerInset.top)
        let railColor = UIColor.tertiaryLabel.withAlphaComponent(0.72)
        let baseSize = font?.pointSize ?? 16
        let railWidth: CGFloat = baseSize >= 17 ? 1.0 : 0.85
        let fullRange = NSRange(location: 0, length: storage.length)

        struct QuoteLinePrefix {
            let prefixRange: NSRange
            let lineRange: NSRange
        }

        var prefixes: [QuoteLinePrefix] = []
        storage.enumerateAttribute(.groveQuotePrefix, in: fullRange, options: []) { value, range, _ in
            guard let isQuotePrefix = value as? Bool, isQuotePrefix, range.length > 0 else { return }

            if selection.length > 0, NSIntersectionRange(selection, range).length > 0 { return }
            if selection.length == 0, selection.location >= range.location, selection.location < range.location + range.length {
                return
            }

            let fullLineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
            let lineRange = trimmedLineRange(fullLineRange, in: nsText, fallback: range)
            prefixes.append(QuoteLinePrefix(prefixRange: range, lineRange: lineRange))
        }

        guard !prefixes.isEmpty else { return }
        prefixes.sort { $0.lineRange.location < $1.lineRange.location }

        struct QuoteBlock {
            var firstPrefixLocation: Int
            var blockLineRange: NSRange
        }

        var blocks: [QuoteBlock] = []
        for entry in prefixes {
            if var last = blocks.last {
                let lastEnd = last.blockLineRange.location + last.blockLineRange.length
                let currentEnd = entry.lineRange.location + entry.lineRange.length
                if entry.lineRange.location <= lastEnd + 2 {
                    last.blockLineRange = NSRange(
                        location: last.blockLineRange.location,
                        length: max(lastEnd, currentEnd) - last.blockLineRange.location
                    )
                    blocks[blocks.count - 1] = last
                    continue
                }
            }

            blocks.append(
                QuoteBlock(
                    firstPrefixLocation: entry.prefixRange.location,
                    blockLineRange: entry.lineRange
                )
            )
        }

        for block in blocks {
            let markerCharRange = NSRange(location: block.firstPrefixLocation, length: 1)
            let markerGlyphRange = lm.glyphRange(forCharacterRange: markerCharRange, actualCharacterRange: nil)
            let blockGlyphRange = lm.glyphRange(forCharacterRange: block.blockLineRange, actualCharacterRange: nil)
            guard markerGlyphRange.length > 0, blockGlyphRange.length > 0 else { continue }

            var markerRect = lm.boundingRect(forGlyphRange: markerGlyphRange, in: container)
            var blockRect = lm.boundingRect(forGlyphRange: blockGlyphRange, in: container)
            markerRect.origin.x += textOrigin.x
            markerRect.origin.y += textOrigin.y
            blockRect.origin.x += textOrigin.x
            blockRect.origin.y += textOrigin.y
            guard blockRect.intersects(dirtyRect) else { continue }

            let railRect = CGRect(
                x: markerRect.minX + 1.4,
                y: blockRect.minY + 1,
                width: railWidth,
                height: max(10, blockRect.height - 2)
            )

            railColor.setFill()
            UIBezierPath(roundedRect: railRect, cornerRadius: railWidth / 2).fill()
        }
    }

    // MARK: - Helpers

    private func trimmedLineRange(_ lineRange: NSRange, in text: NSString, fallback: NSRange) -> NSRange {
        guard lineRange.length > 0 else { return fallback }

        let lineStart = lineRange.location
        var lineEnd = lineRange.location + lineRange.length
        while lineEnd > lineStart {
            let scalar = text.character(at: lineEnd - 1)
            if scalar == 10 || scalar == 13 {
                lineEnd -= 1
            } else {
                break
            }
        }

        let trimmedLength = lineEnd - lineStart
        if trimmedLength > 0 {
            return NSRange(location: lineStart, length: trimmedLength)
        }
        return fallback
    }

    private func splitOuterWhitespace(_ text: String) -> (leading: String, core: String, trailing: String) {
        var start = text.startIndex
        while start < text.endIndex, text[start].isWhitespace {
            start = text.index(after: start)
        }

        var end = text.endIndex
        while end > start {
            let before = text.index(before: end)
            if text[before].isWhitespace {
                end = before
            } else {
                break
            }
        }

        return (
            leading: String(text[..<start]),
            core: String(text[start..<end]),
            trailing: String(text[end...])
        )
    }

    private func utf16Length(of text: String) -> Int {
        (text as NSString).length
    }

    private func selectedLineBlockRange(in text: NSString, selection: NSRange) -> NSRange {
        let safeStart = min(max(0, selection.location), text.length)
        let startLine = text.lineRange(for: NSRange(location: safeStart, length: 0))

        let endAnchor: Int
        if selection.length > 0 {
            endAnchor = max(selection.location, selection.location + selection.length - 1)
        } else {
            endAnchor = safeStart
        }
        let safeEnd = min(max(0, endAnchor), max(0, text.length - (text.length == 0 ? 0 : 1)))
        let endLine = text.lineRange(for: NSRange(location: safeEnd, length: 0))

        let upperBound = endLine.location + endLine.length
        return NSRange(location: startLine.location, length: upperBound - startLine.location)
    }

    private func lineRemovingHeadingPrefix(_ line: String) -> String {
        var index = line.startIndex
        var hashCount = 0
        while index < line.endIndex && line[index] == "#" && hashCount < 6 {
            hashCount += 1
            index = line.index(after: index)
        }

        guard hashCount > 0, index < line.endIndex, line[index] == " " else {
            return line
        }

        return String(line[line.index(after: index)...])
    }
}
#endif
