import Foundation

@MainActor
final class MarkdownEditingProxy {
    struct Actions {
        var wrapSelection: ((String, String) -> Void)?
        var insertPrefix: ((String) -> Void)?
        var insertText: ((String, Int) -> Void)?
        var setHeading: ((Int) -> Void)?
        var toggleBlockQuote: (() -> Void)?
        var toggleListItem: (() -> Void)?
        var insertLink: (() -> Void)?
        var insertWikiLink: (() -> Void)?
        var replaceActiveWikiQuery: ((String) -> Void)?
        /// Replaces the `/query` before the caret; the Int is the caret's
        /// offset back from the end of the inserted text.
        var replaceActiveSlashQuery: ((String, Int) -> Void)?
        /// Nests (false) or un-nests (true) the list lines at the selection.
        var shiftList: ((Bool) -> Void)?
        /// Puts the caret in the editor.
        var focus: (() -> Void)?
    }

    private var actions = Actions()

    func update(_ actions: Actions) {
        self.actions = actions
    }

    func clear() {
        actions = Actions()
    }

    /// True while a mounted editor is listening. A host that wants to insert
    /// at the caret checks this before falling back to editing the string.
    var isConnected: Bool {
        actions.insertText != nil
    }

    func wrapSelection(prefix: String, suffix: String) {
        actions.wrapSelection?(prefix, suffix)
    }

    func insertPrefix(_ prefix: String) {
        actions.insertPrefix?(prefix)
    }

    func insertText(_ text: String, cursorOffset: Int) {
        actions.insertText?(text, cursorOffset)
    }

    func setHeading(level: Int) {
        actions.setHeading?(level)
    }

    func toggleBlockQuote() {
        actions.toggleBlockQuote?()
    }

    func toggleListItem() {
        actions.toggleListItem?()
    }

    func insertLink() {
        actions.insertLink?()
    }

    func insertWikiLink() {
        actions.insertWikiLink?()
    }

    func replaceActiveWikiQuery(with title: String) {
        actions.replaceActiveWikiQuery?(title)
    }

    func replaceActiveSlashQuery(with insertion: String, cursorOffset: Int) {
        actions.replaceActiveSlashQuery?(insertion, cursorOffset)
    }

    func shiftList(outward: Bool) {
        actions.shiftList?(outward)
    }

    func focus() {
        actions.focus?()
    }
}
