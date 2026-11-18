import Foundation
import Testing
@testable import grove

/// What the editor decides the caret is in the middle of typing, and what
/// the `/` menu offers for it.
struct EditorAssistTests {
    @Test func wikiLinkTriggersFromTheOpeningBracketsToTheCaret() {
        let detected = EditorAssistTrigger.detect(linePrefix: "see [[Deep W")
        #expect(detected?.trigger == .wikiLink(query: "Deep W"))
        // `[[Deep W` is what a pick replaces.
        #expect(detected?.tokenLength == 8)

        #expect(EditorAssistTrigger.detect(linePrefix: "[[")?.trigger == .wikiLink(query: ""))
    }

    @Test func aClosedWikiLinkNoLongerTriggers() {
        #expect(EditorAssistTrigger.detect(linePrefix: "see [[Deep Work]] and") == nil)
        // The most recent `[[` is the one that counts.
        #expect(EditorAssistTrigger.detect(linePrefix: "[[One]] then [[Tw")?.trigger == .wikiLink(query: "Tw"))
    }

    @Test func slashOnlyTriggersAtTheStartOfALine() {
        #expect(EditorAssistTrigger.detect(linePrefix: "/")?.trigger == .slash(query: ""))
        #expect(EditorAssistTrigger.detect(linePrefix: "  /qu")?.trigger == .slash(query: "qu"))
        #expect(EditorAssistTrigger.detect(linePrefix: "/qu")?.tokenLength == 3)

        #expect(EditorAssistTrigger.detect(linePrefix: "and/or") == nil)
        #expect(EditorAssistTrigger.detect(linePrefix: "https://example.com/pa") == nil)
        #expect(EditorAssistTrigger.detect(linePrefix: "on 3/4") == nil)
        // A space ends the command.
        #expect(EditorAssistTrigger.detect(linePrefix: "/quote this") == nil)
    }

    @Test func tokenLengthCountsUTF16SoTheReplacementRangeIsRight() {
        // The tree is two UTF-16 units; the text view counts in those.
        let detected = EditorAssistTrigger.detect(linePrefix: "x [[🌲a")
        #expect(detected?.trigger == .wikiLink(query: "🌲a"))
        #expect(detected?.tokenLength == 5)
    }

    @Test func blockCommandsMatchByTitleAndKeyword() {
        #expect(EditorBlockCommand.matching("").count == EditorBlockCommand.all.count)
        #expect(EditorBlockCommand.matching("todo").map(\.id) == ["task"])
        #expect(EditorBlockCommand.matching("h2").map(\.id) == ["h2"])
        #expect(EditorBlockCommand.matching("QUO").map(\.id) == ["quote"])
        #expect(EditorBlockCommand.matching("head").map(\.id) == ["h1", "h2", "h3"])
        #expect(EditorBlockCommand.matching("zzz").isEmpty)
    }

    @Test func blockCommandIdentifiersAreUnique() {
        let ids = EditorBlockCommand.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func codeBlockLeavesTheCaretOnItsEmptyLine() throws {
        let code = try #require(EditorBlockCommand.all.first { $0.id == "code" })
        let caret = (code.insertion as NSString).length + code.cursorOffset
        #expect((code.insertion as NSString).substring(to: caret) == "```\n")
    }
}
