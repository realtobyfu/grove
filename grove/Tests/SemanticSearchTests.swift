import Foundation
import SwiftData
import Testing
@testable import grove

/// Covers the "Related by meaning" merge rule without touching the embedding index.
struct SemanticSearchTests {
    private let threshold = 0.4

    private func candidate(_ id: UUID, _ score: Double) -> SemanticCandidate {
        SemanticCandidate(id: id, score: score)
    }

    private func matches(
        _ candidates: [SemanticCandidate],
        fuzzy: Set<UUID> = [],
        excluded: Set<UUID> = [],
        limit: Int = 8
    ) -> [SemanticCandidate] {
        SearchViewModel.semanticMatches(
            candidates: candidates,
            fuzzyIDs: fuzzy,
            excludedIDs: excluded,
            threshold: threshold,
            limit: limit
        )
    }

    @Test func dropsCandidatesBelowThresholdAndKeepsThoseAtIt() {
        let below = UUID(), atThreshold = UUID(), above = UUID()

        let result = matches([
            candidate(below, 0.399),
            candidate(atThreshold, 0.4),
            candidate(above, 0.47),
        ])

        #expect(result.map(\.id) == [above, atThreshold])
    }

    @Test func excludesItemsAlreadyShownAsFuzzyMatches() {
        let exact = UUID(), related = UUID()

        let result = matches(
            [candidate(exact, 0.9), candidate(related, 0.5)],
            fuzzy: [exact]
        )

        #expect(result.map(\.id) == [related])
    }

    @Test func excludesArchivedAndDismissedIDs() {
        let archived = UUID(), dismissed = UUID(), active = UUID()

        let result = matches(
            [candidate(archived, 0.8), candidate(dismissed, 0.7), candidate(active, 0.45)],
            excluded: [archived, dismissed]
        )

        #expect(result.map(\.id) == [active])
    }

    @Test func ordersByScoreDescendingAndCapsAtLimit() {
        let ids = (0..<12).map { _ in UUID() }
        let candidates = ids.enumerated().map { offset, id in
            candidate(id, 0.41 + Double(offset) * 0.01)
        }

        let result = matches(candidates.shuffled(), limit: 8)

        #expect(result.count == 8)
        #expect(result.map(\.id) == Array(ids.reversed().prefix(8)))
        #expect(result.map(\.score) == result.map(\.score).sorted(by: >))
    }

    @Test func limitAppliesAfterExclusions() {
        let shown = UUID(), archived = UUID(), first = UUID(), second = UUID()

        let result = matches(
            [candidate(shown, 0.9), candidate(archived, 0.8), candidate(first, 0.6), candidate(second, 0.5)],
            fuzzy: [shown],
            excluded: [archived],
            limit: 2
        )

        #expect(result.map(\.id) == [first, second])
    }

    @Test func duplicateCandidateKeepsItsBestScore() {
        let id = UUID()

        let result = matches([candidate(id, 0.42), candidate(id, 0.61), candidate(id, 0.3)])

        #expect(result == [candidate(id, 0.61)])
    }

    @Test func equalScoresHaveAStableOrder() {
        let a = UUID(), b = UUID(), c = UUID()
        let forward = matches([candidate(a, 0.5), candidate(b, 0.5), candidate(c, 0.5)])
        let reversed = matches([candidate(c, 0.5), candidate(b, 0.5), candidate(a, 0.5)])

        #expect(forward == reversed)
        #expect(forward.map(\.id.uuidString) == [a, b, c].map(\.uuidString).sorted())
    }

    @Test func nonPositiveLimitOrNoCandidatesReturnsNothing() {
        #expect(matches([candidate(UUID(), 0.9)], limit: 0).isEmpty)
        #expect(matches([candidate(UUID(), 0.9)], limit: -1).isEmpty)
        #expect(matches([]).isEmpty)
    }

    @Test func nonFiniteScoresNeverPass() {
        #expect(matches([candidate(UUID(), .nan)]).isEmpty)
    }

    @Test func shippedTuningMatchesTheDesign() {
        #expect(SearchViewModel.semanticResultLimit == 8)
        #expect(SearchViewModel.semanticMinimumQueryLength == 3)
        #expect(SearchViewModel.semanticScoreThreshold > 0)
        #expect(SearchViewModel.semanticScoreThreshold < 1)
    }

    /// An empty index (a private, never-written cache file, not the shared one)
    /// leaves exact matches untouched and produces no semantic section.
    @MainActor
    @Test func emptyIndexProducesNoSemanticSection() async throws {
        let container = try ModelContainer(
            for: SharedModelContainer.schema,
            configurations: [ModelConfiguration(
                "SemanticSearchTests",
                schema: SharedModelContainer.schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )]
        )
        let context = ModelContext(container)
        context.insert(Item(title: "Spaced repetition notes", type: .note))
        try context.save()

        let emptyIndex = EmbeddingIndexService(
            cacheURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("semantic-search-tests-\(UUID().uuidString).json")
        )
        let viewModel = SearchViewModel(
            modelContext: context,
            debounceNanoseconds: 10_000_000,
            semanticDebounceNanoseconds: 10_000_000,
            embeddingIndex: emptyIndex
        )

        viewModel.updateQuery("spaced")
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(viewModel.totalResultCount == 1)
        #expect(viewModel.semanticResults.isEmpty)
        #expect(viewModel.hasAnyResults)
    }
}
