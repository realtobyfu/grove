import Testing
@testable import grove

/// Nested lists: what Tab, Shift-Tab and Return do to list lines.
struct MarkdownListEditingTests {

    // MARK: - Reading lines

    @Test func readsBulletsTasksAndNumbersAtAnyDepth() {
        #expect(MarkdownListEditing.listLine("- Top")?.kind == .bullet(marker: "-"))
        #expect(MarkdownListEditing.listLine("  * Nested")?.level == 1)
        #expect(MarkdownListEditing.listLine("    - [x] Done")?.kind == .task(marker: "-"))
        #expect(MarkdownListEditing.listLine("    - [x] Done")?.level == 2)
        #expect(MarkdownListEditing.listLine("  3) Third")?.kind == .ordered(number: 3, delimiter: ")"))
    }

    @Test func aMarkerNeedsASpaceAfterIt() {
        #expect(MarkdownListEditing.listLine("-") == nil)
        #expect(MarkdownListEditing.listLine("---") == nil)
        #expect(MarkdownListEditing.listLine("*emphasis*") == nil)
        #expect(MarkdownListEditing.listLine("2024 was a year") == nil)
        #expect(MarkdownListEditing.listLine("Plain text") == nil)
    }

    // MARK: - Tab and Shift-Tab

    @Test func tabNestsListLinesByTwoSpaces() throws {
        let result = try #require(MarkdownListEditing.shifted(["- One", "- Two"], outward: false))
        #expect(result.lines == ["  - One", "  - Two"])
        #expect(result.deltas == [2, 2])
    }

    @Test func tabLeavesOtherLinesAlone() throws {
        let result = try #require(MarkdownListEditing.shifted(["Intro", "- Item", ""], outward: false))
        #expect(result.lines == ["Intro", "  - Item", ""])
        #expect(result.deltas == [0, 2, 0])
    }

    @Test func tabOnPlainTextChangesNothing() {
        #expect(MarkdownListEditing.shifted(["Just a sentence."], outward: false) == nil)
    }

    @Test func tabStopsAtTheDeepestLevel() {
        let deepest = String(repeating: "  ", count: MarkdownTypeSpec.maxNestingLevel) + "- Deep"
        #expect(MarkdownListEditing.shifted([deepest], outward: false) == nil)
    }

    @Test func aNestedNumberedItemStartsItsLevelAtOne() throws {
        let result = try #require(MarkdownListEditing.shifted(["2. Second"], outward: false))
        #expect(result.lines == ["  1. Second"])
        #expect(result.deltas == [2])
    }

    @Test func shiftTabBringsLinesOutOneLevel() throws {
        let result = try #require(MarkdownListEditing.shifted(["    - Deep", "  - Nested", "- Top"], outward: true))
        #expect(result.lines == ["  - Deep", "- Nested", "- Top"])
        #expect(result.deltas == [-2, -2, 0])
    }

    @Test func shiftTabRemovesALeadingTab() throws {
        let result = try #require(MarkdownListEditing.shifted(["\t- Tabbed"], outward: true))
        #expect(result.lines == ["- Tabbed"])
    }

    @Test func shiftTabOnTopLevelItemsChangesNothing() {
        #expect(MarkdownListEditing.shifted(["- Top", "- Also top"], outward: true) == nil)
    }

    // MARK: - Return

    @Test func returnContinuesAtTheSameDepth() {
        #expect(MarkdownListEditing.returnAction(for: "- One") == .continueWith("- "))
        #expect(MarkdownListEditing.returnAction(for: "  - Nested") == .continueWith("  - "))
        #expect(MarkdownListEditing.returnAction(for: "  - [x] Done") == .continueWith("  - [ ] "))
        #expect(MarkdownListEditing.returnAction(for: "  1. First") == .continueWith("  2. "))
    }

    @Test func returnOnAnEmptyNestedItemStepsOutALevel() {
        #expect(MarkdownListEditing.returnAction(for: "  - ") == .outdent("- "))
        #expect(MarkdownListEditing.returnAction(for: "    - [ ] ") == .outdent("  - [ ] "))
    }

    @Test func returnOnAnEmptyTopLevelItemEndsTheList() {
        #expect(MarkdownListEditing.returnAction(for: "- ") == .endList)
        #expect(MarkdownListEditing.returnAction(for: "- [ ]") == .endList)
        #expect(MarkdownListEditing.returnAction(for: "1. ") == .endList)
    }

    @Test func returnOutsideAListIsUntouched() {
        #expect(MarkdownListEditing.returnAction(for: "A sentence") == .notAList)
        #expect(MarkdownListEditing.returnAction(for: "-") == .notAList)
    }

    // MARK: - Levels

    @Test func nestingLevelsAreTwoSpacesEachUpToTheLimit() {
        #expect(MarkdownTypeSpec.nestingLevel(forIndentation: 0) == 0)
        #expect(MarkdownTypeSpec.nestingLevel(forIndentation: 1) == 0)
        #expect(MarkdownTypeSpec.nestingLevel(forIndentation: 2) == 1)
        #expect(MarkdownTypeSpec.nestingLevel(forIndentation: 4) == 2)
        #expect(MarkdownTypeSpec.nestingLevel(forIndentation: 40) == MarkdownTypeSpec.maxNestingLevel)
    }
}
