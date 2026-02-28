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
    }

    private var actions = Actions()

    func update(_ actions: Actions) {
        self.actions = actions
    }

    func clear() {
        actions = Actions()
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
}
