import Foundation
import SwiftData
import Testing
@testable import grove

/// AI overviews sit beside an item's content and never replace it, and items
/// overviewed before that was true move across without losing either text.
@MainActor
struct ItemOverviewTests {
    private let original = "A short description of the page."
    private let generated = "The article argues that moss outlives its rivals. It backs this with decades of field data."

    private func makeItem() -> Item {
        Item(title: "Moss", type: .article)
    }

    /// The shape older builds left: overview in `content`, the replaced text
    /// in `originalDescription`.
    private func makeLegacyItem(content: String?) -> Item {
        let item = makeItem()
        item.content = content
        item.originalDescription = original
        item.hasLLMOverview = true
        return item
    }

    private func expectContentKept(_ item: Item, content: String?) {
        #expect(item.content == content)
        #expect(item.overview == nil)
        #expect(item.originalDescription == original)
        #expect(item.hasLLMOverview)
    }

    // MARK: - Storage

    @Test func overviewIsStoredInItsOwnMetadataKey() {
        let item = makeItem()
        #expect(item.overview == nil)
        item.overview = generated
        #expect(item.metadata["overview"] == generated)
        item.overview = nil
        #expect(item.metadata["overview"] == nil)
    }

    @Test func recordingAnOverviewLeavesContentAlone() {
        let item = makeItem()
        item.content = original
        item.recordOverview(generated)

        #expect(item.content == original)
        #expect(item.overview == generated)
        #expect(!item.hasLLMOverview)
        #expect(item.originalDescription == nil)
    }

    @Test func regeneratingReplacesOnlyTheOverview() {
        let item = makeItem()
        item.content = original
        item.recordOverview(generated)
        item.recordOverview("A newer overview.")

        #expect(item.content == original)
        #expect(item.overview == "A newer overview.")
    }

    @Test func recordingOnALegacyItemMigratesItFirst() {
        let item = makeLegacyItem(content: generated)
        item.recordOverview("A newer overview.")

        #expect(item.content == original)
        #expect(item.overview == "A newer overview.")
        #expect(item.originalDescription == nil)
    }

    // MARK: - Migration

    @Test func legacyItemMovesBothTextsToTheirPlaces() {
        let item = makeLegacyItem(content: generated)

        #expect(item.migrateLegacyOverviewIfNeeded())
        #expect(item.content == original)
        #expect(item.overview == generated)
        #expect(item.originalDescription == nil)
        #expect(!item.hasLLMOverview)
    }

    @Test func migrationIsIdempotent() {
        let item = makeLegacyItem(content: generated)
        item.migrateLegacyOverviewIfNeeded()
        let metadata = item.metadata

        #expect(!item.migrateLegacyOverviewIfNeeded())
        #expect(item.content == original)
        #expect(item.overview == generated)
        #expect(item.metadata == metadata)
    }

    @Test func migrationDoesNotTouchUpdatedAt() {
        let item = makeLegacyItem(content: generated)
        let stamp = Date(timeIntervalSince1970: 1_000)
        item.updatedAt = stamp

        item.migrateLegacyOverviewIfNeeded()
        #expect(item.updatedAt == stamp)
    }

    @Test(arguments: [
        "See [[Moss Ecology]] for the follow-up.",
        "My notes\n\n# What matters\n\nThe field data.",
        "Takeaways:\n- moss outlives rivals\n- field data",
        "Takeaways:\n  * indented bullet",
        "> a line I kept from the piece",
        "Takeaways:\n1. first\n2. second",
    ])
    func contentCarryingEditsStaysPut(edited: String) {
        let item = makeLegacyItem(content: edited)

        #expect(item.migrateLegacyOverviewIfNeeded())
        expectContentKept(item, content: edited)
    }

    @Test(arguments: [nil, "", "  \n "] as [String?])
    func clearedContentStaysCleared(cleared: String?) {
        let item = makeLegacyItem(content: cleared)

        item.migrateLegacyOverviewIfNeeded()
        expectContentKept(item, content: cleared)
    }

    @Test func keptEditIsDecidedOnce() {
        let edited = "See [[Moss Ecology]] for the follow-up."
        let item = makeLegacyItem(content: edited)
        item.migrateLegacyOverviewIfNeeded()

        // The edit marker going away later must not re-open the decision.
        item.content = "Now it reads like plain prose."
        #expect(!item.migrateLegacyOverviewIfNeeded())
        expectContentKept(item, content: "Now it reads like plain prose.")
    }

    @Test func aPlainProseEditCannotBeToldApartButNeitherTextIsLost() {
        // The generated text was never stored, so nothing distinguishes this
        // from an untouched overview. Pinned so the limit stays visible.
        let edited = generated + " I think this undersells the drought years."
        let item = makeLegacyItem(content: edited)

        #expect(item.migrateLegacyOverviewIfNeeded())
        #expect(item.overview == edited)
        #expect(item.content == original)
    }

    @Test func contentAlreadyBackToTheOriginalJustClearsTheLegacyState() {
        let item = makeLegacyItem(content: "  \(original)\n")

        #expect(item.migrateLegacyOverviewIfNeeded())
        #expect(item.content == "  \(original)\n")
        #expect(item.overview == nil)
        #expect(item.originalDescription == nil)
        #expect(!item.hasLLMOverview)
    }

    @Test func legacyItemThatReplacedNothingStaysLabelledAsAIText() {
        let item = makeItem()
        item.content = generated
        item.hasLLMOverview = true

        #expect(!item.migrateLegacyOverviewIfNeeded())
        #expect(item.content == generated)
        #expect(item.overview == nil)
        #expect(item.hasLLMOverview)
    }

    @Test func itemsThatWereNeverOverviewedAreUntouched() {
        let item = makeItem()
        item.content = original
        // A leftover with no flag is not an overviewed item.
        item.originalDescription = "stale"

        #expect(!item.migrateLegacyOverviewIfNeeded())
        #expect(item.content == original)
        #expect(item.overview == nil)
    }

    // MARK: - Re-overviewed by an older build

    /// An older build on another device re-overviewed an item that was
    /// already migrated: `overview` is set, yet `content` is AI text again.
    @Test func mixedStateWithAGeneratedOverviewTakesTheNewerText() {
        let item = makeItem()
        item.content = original
        item.recordOverview("The first overview.")
        // What the old build writes.
        item.originalDescription = original
        item.content = generated
        item.hasLLMOverview = true

        #expect(item.migrateLegacyOverviewIfNeeded())
        #expect(item.overview == generated)
        #expect(item.content == original)
        #expect(item.originalDescription == nil)
        #expect(!item.hasLLMOverview)
        #expect(!item.canReplaceOverview)
        #expect(!item.migrateLegacyOverviewIfNeeded())
    }

    @Test func mixedStateNeverReplacesAnOverviewThatMayBeTheUsers() {
        // Moved out of a legacy `content`, so possibly a plain-prose edit.
        let moved = makeLegacyItem(content: "Words the user may have written.")
        moved.migrateLegacyOverviewIfNeeded()
        // Written before the generated marker existed.
        let unmarked = makeItem()
        unmarked.overview = "Already here."

        for (item, kept) in [(moved, "Words the user may have written."), (unmarked, "Already here.")] {
            item.originalDescription = original
            item.content = generated
            item.hasLLMOverview = true

            #expect(item.migrateLegacyOverviewIfNeeded())
            #expect(item.overview == kept)
            #expect(item.content == original)
            #expect(item.originalDescription == nil)
            #expect(!item.hasLLMOverview)
        }
    }

    @Test func mixedStateWithAnEditedContentStaysPut() {
        let item = makeItem()
        item.recordOverview("The first overview.")
        item.originalDescription = original
        item.content = "See [[Moss Ecology]] for the follow-up."
        item.hasLLMOverview = true

        #expect(item.migrateLegacyOverviewIfNeeded())
        #expect(item.overview == "The first overview.")
        #expect(item.content == "See [[Moss Ecology]] for the follow-up.")
        #expect(item.originalDescription == original)
        #expect(item.hasLLMOverview)
    }

    @Test func thePassRepairsAMixedStateItem() throws {
        let context = try makeInMemoryModelContext()
        let item = makeItem()
        item.recordOverview("The first overview.")
        item.originalDescription = original
        item.content = generated
        item.hasLLMOverview = true
        context.insert(item)
        try context.save()

        OverviewMigrationService.migrateItems(context: context)
        #expect(!context.hasChanges)
        #expect(item.overview == generated)
        #expect(item.content == original)
    }

    // MARK: - Which overviews a refresh may regenerate

    @Test func onlyAGeneratedOverviewCanBeReplaced() {
        let empty = makeItem()
        #expect(empty.canReplaceOverview)

        let generatedItem = makeItem()
        generatedItem.recordOverview(generated)
        #expect(generatedItem.canReplaceOverview)

        let unmarked = makeItem()
        unmarked.overview = generated
        #expect(!unmarked.canReplaceOverview)

        let moved = makeLegacyItem(content: generated)
        moved.migrateLegacyOverviewIfNeeded()
        #expect(moved.overview == generated)
        #expect(!moved.canReplaceOverview)
    }

    @Test func theRefreshCheckMigratesALegacyItemBeforeDeciding() throws {
        let context = try makeInMemoryModelContext()
        let legacy = makeLegacyItem(content: generated)
        context.insert(legacy)
        try context.save()

        let enricher = ItemMetadataEnricher()
        #expect(!enricher.overviewMayBeReplaced(itemID: legacy.id, context: context))
        #expect(legacy.overview == generated)
        #expect(legacy.content == original)
    }

    // MARK: - Refreshing metadata

    private func makeEnricher(_ metadata: URLMetadata) -> ItemMetadataEnricher {
        let fetcher = MockURLMetadataFetcher()
        fetcher.result = metadata
        return ItemMetadataEnricher(metadataFetcher: fetcher, imageDownloader: MockImageDownloadService())
    }

    private let pageURL = "https://example.com/moss"
    private var fetched: URLMetadata {
        URLMetadata(title: "Fetched Title", description: "Fetched description.", authors: "R. Kimmerer")
    }

    @Test func refreshKeepsTheUsersTitleAndContent() async throws {
        let context = try makeInMemoryModelContext()
        let item = makeItem()
        item.title = "My name for it"
        item.content = "Notes I wrote."
        item.sourceURL = pageURL
        context.insert(item)
        try context.save()

        _ = await makeEnricher(fetched).enrichURLItem(
            itemID: item.id, urlString: pageURL, context: context, overwrite: .refresh
        )
        #expect(item.title == "My name for it")
        #expect(item.content == "Notes I wrote.")
        #expect(item.authors == "R. Kimmerer")
    }

    @Test(arguments: ["https://example.com/moss", "example.com", "www.example.com", ""])
    func refreshFillsAPlaceholderTitleAndEmptyContent(placeholder: String) async throws {
        let context = try makeInMemoryModelContext()
        let item = makeItem()
        item.title = placeholder
        item.content = nil
        item.sourceURL = pageURL
        context.insert(item)
        try context.save()

        _ = await makeEnricher(fetched).enrichURLItem(
            itemID: item.id, urlString: pageURL, context: context, overwrite: .refresh
        )
        #expect(item.title == "Fetched Title")
        #expect(item.content == "Fetched description.")
    }

    @Test func initialCaptureStillReplacesTitleAndContent() async throws {
        let context = try makeInMemoryModelContext()
        let item = makeItem()
        item.title = "Something else"
        item.content = "Old"
        item.sourceURL = pageURL
        context.insert(item)
        try context.save()

        _ = await makeEnricher(fetched).enrichURLItem(itemID: item.id, urlString: pageURL, context: context)
        #expect(item.title == "Fetched Title")
        #expect(item.content == "Fetched description.")
    }

    @Test func thePassMigratesAStoreAndPersistsTheResult() throws {
        let context = try makeInMemoryModelContext()
        let legacy = makeLegacyItem(content: generated)
        let edited = makeLegacyItem(content: "See [[Moss Ecology]].")
        let plain = makeItem()
        plain.content = original
        for item in [legacy, edited, plain] { context.insert(item) }
        try context.save()

        OverviewMigrationService.migrateItems(context: context)
        #expect(!context.hasChanges)
        #expect(legacy.content == original)
        #expect(legacy.overview == generated)
        expectContentKept(edited, content: "See [[Moss Ecology]].")
        #expect(plain.content == original)

        OverviewMigrationService.migrateItems(context: context)
        #expect(!context.hasChanges)
        #expect(legacy.content == original)
        #expect(legacy.overview == generated)
    }

    @Test func theReaderViewModelCatchesAnItemThatSyncedInLate() throws {
        let context = try makeInMemoryModelContext()
        let legacy = makeLegacyItem(content: generated)
        context.insert(legacy)
        try context.save()

        ItemReaderViewModel(item: legacy, modelContext: context).migrateLegacyOverviewIfNeeded()
        #expect(legacy.overview == generated)
        #expect(!context.hasChanges)
    }

    // MARK: - Editing

    @Test func articlesWithAnOverviewKeepTheirEditButton() throws {
        let context = try makeInMemoryModelContext()
        let plain = makeItem()
        let overviewed = makeItem()
        overviewed.overview = generated
        let keptEdit = makeLegacyItem(content: "See [[Moss Ecology]].")
        let note = Item(title: "Note", type: .note)

        func canEdit(_ item: Item) -> Bool {
            ItemReaderViewModel(item: item, modelContext: context).canEditContent
        }
        #expect(!canEdit(plain))
        #expect(canEdit(overviewed))
        #expect(canEdit(keptEdit))
        #expect(canEdit(note))
    }

    // MARK: - Summary fallback

    @Test func summaryFallbackPrefersTheOverview() throws {
        let context = try makeInMemoryModelContext()
        let item = makeItem()
        item.content = original
        item.recordOverview(generated)
        context.insert(item)
        try context.save()

        ItemMetadataEnricher().extractSummaryFallback(itemID: item.id, context: context)
        #expect(item.summary == "The article argues that moss outlives its rivals")
    }

    // MARK: - What reads the overview

    @Test func retrievalTextJoinsWhatEachItemHas() {
        let item = makeItem()
        #expect(item.retrievalText.isEmpty)

        item.overview = generated
        #expect(item.retrievalText == generated)

        item.content = original
        #expect(item.retrievalText == "\(original)\n\n\(generated)")

        item.overview = nil
        #expect(item.retrievalText == original)
    }

    @Test func previewTextPrefersContent() {
        let item = makeItem()
        #expect(item.previewText == nil)

        item.overview = generated
        #expect(item.previewText == generated)

        item.content = ""
        #expect(item.previewText == generated)

        item.content = original
        #expect(item.previewText == original)
    }

    @Test func chatContextLabelsTheOverviewAsAIText() {
        let item = makeItem()
        item.content = original
        item.overview = generated

        let description = LLMContextBuilder.itemDescription(item)
        #expect(description.contains("Content excerpt: \(original)"))
        #expect(description.contains("AI overview: \(generated)"))

        let withoutContent = LLMContextBuilder.itemDescription(item, includeContent: false)
        #expect(!withoutContent.contains(generated))
    }

    @Test func embeddingsSeeBothTexts() {
        let item = makeItem()
        item.content = original
        item.overview = generated

        let text = EmbeddingIndexService.snapshot(item).text
        #expect(text.contains(original))
        #expect(text.contains(generated))
    }

    @Test func exportKeepsTheOverviewUnderItsOwnHeading() {
        let item = makeItem()
        item.content = original
        item.overview = generated

        let markdown = ExportService.markdownForItem(item)
        #expect(markdown.contains("## Content\n\n\(original)"))
        #expect(markdown.contains("## AI Overview\n\n\(generated)"))
    }

    // MARK: - Helpers

    private func makeInMemoryModelContext() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let config = ModelConfiguration(
            "ItemOverviewTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
