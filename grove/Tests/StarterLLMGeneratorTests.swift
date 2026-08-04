import Foundation
import Testing
@testable import grove

struct StarterLLMGeneratorTests {
    @Test func sanitizePromptStripsLeakedContextIDs() {
        let raw = "How does the tension between CoW and AI agents (stale_1) reflect a divide?"
        let cleaned = StarterLLMGenerator.sanitizePrompt(raw, candidateIDs: ["stale_0", "stale_1", "recent_items"])
        #expect(cleaned == "How does the tension between CoW and AI agents reflect a divide?")
    }

    @Test func sanitizePromptStripsBareMachineLookingIDs() {
        let raw = "Does stale_1 still hold up a month later?"
        let cleaned = StarterLLMGenerator.sanitizePrompt(raw, candidateIDs: ["stale_0", "stale_1"])
        #expect(cleaned == "Does still hold up a month later?")
    }

    @Test func sanitizePromptKeepsEnglishWordsThatDoubleAsContextIDs() {
        // "contradiction" and "general" are real IDs *and* real words. Stripping
        // them bare gutted otherwise-good questions.
        let raw = "Want to work through the contradiction between X and Y?"
        let cleaned = StarterLLMGenerator.sanitizePrompt(
            raw,
            candidateIDs: ["contradiction", "recent_items"]
        )
        #expect(cleaned == raw)

        let general = "What is the general shape of the argument?"
        #expect(StarterLLMGenerator.sanitizePrompt(general, candidateIDs: []) == general)
    }

    @Test func sanitizePromptStillStripsParenthesizedWordLikeIDs() {
        let raw = "Want to work through the contradiction (contradiction) between X and Y?"
        let cleaned = StarterLLMGenerator.sanitizePrompt(raw, candidateIDs: ["contradiction"])
        #expect(cleaned == "Want to work through the contradiction between X and Y?")
    }

    @Test func sanitizePromptDoesNotStripIDsEmbeddedInLongerWords() {
        let raw = "Is stale_10 the same as stale_1?"
        let cleaned = StarterLLMGenerator.sanitizePrompt(raw, candidateIDs: ["stale_1"])
        #expect(cleaned == "Is stale_10 the same as ?")
    }

    @Test func sanitizePromptLeavesCleanTextUntouched(){
        let raw = "What convinced you in that article about Swift's value semantics?"
        let cleaned = StarterLLMGenerator.sanitizePrompt(raw, candidateIDs: ["stale_0", "contradiction"])
        #expect(cleaned == raw)
    }

    @Test func normalizeLabelKeepsCanonicalLabels() {
        #expect(StarterLLMGenerator.normalizeLabel("revisit") == "REVISIT")
        #expect(StarterLLMGenerator.normalizeLabel(" SYNTHESIZE ") == "SYNTHESIZE")
    }

    @Test func normalizeLabelMapsInventedLabels() {
        #expect(StarterLLMGenerator.normalizeLabel("CONTRADICTION") == "RESOLVE")
        #expect(StarterLLMGenerator.normalizeLabel("CONFLICT") == "RESOLVE")
        #expect(StarterLLMGenerator.normalizeLabel("SOMETHING_ELSE") == "EXPLORE")
    }

    @Test func trimmedTitleDropsPublicationSuffix() {
        #expect(
            StarterLLMGenerator.trimmedTitle("AI Broke Code Review. Here's How to Rebuild It ‣ Swift and Memes")
                == "AI Broke Code Review. Here's How to Rebuild It"
        )
        #expect(StarterLLMGenerator.trimmedTitle("Value Semantics in Practice | Some Blog") == "Value Semantics in Practice")
    }

    @Test func trimmedTitleKeepsTitlesWhereTheSeparatorIsPartOfTheHeadline() {
        // Nothing substantial in front of the separator, or a long tail, means
        // the separator belongs to the title rather than a publication byline.
        let short = "Swift | A Language"
        #expect(StarterLLMGenerator.trimmedTitle(short) == short)

        let longTail = "On Abstraction | and why every layer you add has to earn its keep"
        #expect(StarterLLMGenerator.trimmedTitle(longTail) == longTail)

        let emDash = "Code Review — Rebuilt"
        #expect(StarterLLMGenerator.trimmedTitle(emDash) == emDash)
    }

    @MainActor
    @Test func groundingIsNilWhenOnlyTheTitleIsKnown() {
        let item = Item(title: "AI Broke Code Review ‣ Swift and Memes", type: .article)
        #expect(StarterLLMGenerator.grounding(for: item) == nil)

        // Boilerplate scraps are not substance either.
        item.content = "Sign in to continue."
        #expect(StarterLLMGenerator.grounding(for: item) == nil)
    }

    @MainActor
    @Test func groundingPrefersTheStoredSummaryOverRawContent() {
        let item = Item(title: "AI Broke Code Review", type: .article)
        item.content = String(repeating: "boilerplate nav chrome ", count: 10)
        item.metadata["summary"] = "Argues that LLM-authored diffs make reviewer attention the bottleneck."

        let grounding = StarterLLMGenerator.grounding(for: item)
        #expect(grounding == "Argues that LLM-authored diffs make reviewer attention the bottleneck.")
    }

    @MainActor
    @Test func groundingPrefersTheUsersOwnNote() {
        let item = Item(title: "AI Broke Code Review", type: .article)
        item.metadata["summary"] = "A summary."
        let reflection = ReflectionBlock(item: item, blockType: .disagreement, content: "I disagree — review was already broken.", position: 0)
        item.reflections.append(reflection)

        let grounding = StarterLLMGenerator.grounding(for: item)
        #expect(grounding == "their note on it: I disagree — review was already broken.")
    }

    @MainActor
    @Test func recentItemsCandidateIsSkippedWhenNothingIsKnownBeyondTitles() {
        // A starter built on titles alone can only restate the title back as a
        // question, so the whole candidate drops out.
        let bare = Item(title: "AI Broke Code Review ‣ Swift and Memes", type: .article)
        bare.status = .active
        bare.createdAt = .now

        let context = StarterContextBuilder.buildContext(from: [bare])
        let candidates = StarterLLMGenerator.buildCandidates(from: context, didShowClusterBubble: false)

        #expect(!candidates.contains { $0.id == "recent_items" })
    }

    @MainActor
    @Test func recentItemsCandidateCarriesSubstanceNotJustTitles() {
        let item = Item(title: "AI Broke Code Review ‣ Swift and Memes", type: .article)
        item.status = .active
        item.createdAt = .now
        item.metadata["summary"] = "Argues reviewer attention is now the bottleneck."

        let context = StarterContextBuilder.buildContext(from: [item])
        let candidates = StarterLLMGenerator.buildCandidates(from: context, didShowClusterBubble: false)
        let recent = candidates.first { $0.id == "recent_items" }

        #expect(recent?.summary.contains("Argues reviewer attention is now the bottleneck.") == true)
        // The publication name is gone, so it cannot be read as subject matter.
        #expect(recent?.summary.contains("Swift and Memes") == false)
    }

    @Test func parseResponseSanitizesAndNormalizes() throws {
        let raw = """
        [{"prompt": "Is the claim in that article (stale_0) still convincing?", "label": "CONFLICT", "context_id": "stale_0"}]
        """
        let candidates = [
            StarterLLMContextCandidate(id: "stale_0", summary: "s", clusterTag: nil, itemIDs: [], boardIDs: [])
        ]
        let bubbles = try #require(StarterLLMGenerator.parseResponse(raw, candidates: candidates))
        #expect(bubbles.count == 1)
        #expect(bubbles[0].prompt == "Is the claim in that article still convincing?")
        #expect(bubbles[0].label == "RESOLVE")
        #expect(bubbles[0].contextID == "stale_0")
    }
}
