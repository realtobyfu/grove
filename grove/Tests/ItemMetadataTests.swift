import Foundation
import Testing
@testable import grove

/// Pins the typed accessors in `Item+Metadata.swift` to the stored format.
/// Existing and synced items hold these exact strings, so every expectation
/// here spells the legacy key and value out literally: a failure means stored
/// data would stop reading back, not that the test needs updating.
@MainActor
struct ItemMetadataTests {
    private func makeItem(type: ItemType = .article) -> Item {
        Item(title: "Item", type: type)
    }

    private func expectFlag(
        _ keyPath: ReferenceWritableKeyPath<Item, Bool>,
        storedAs key: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let item = makeItem()
        #expect(item[keyPath: keyPath] == false, sourceLocation: sourceLocation)

        item[keyPath: keyPath] = true
        #expect(item.metadata[key] == "true", sourceLocation: sourceLocation)

        item[keyPath: keyPath] = false
        #expect(item.metadata[key] == nil, sourceLocation: sourceLocation)

        item.metadata[key] = "true"
        #expect(item[keyPath: keyPath] == true, sourceLocation: sourceLocation)
    }

    private func expectString(
        _ keyPath: ReferenceWritableKeyPath<Item, String?>,
        storedAs key: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let item = makeItem()
        #expect(item[keyPath: keyPath] == nil, sourceLocation: sourceLocation)

        item[keyPath: keyPath] = "written"
        #expect(item.metadata[key] == "written", sourceLocation: sourceLocation)

        item[keyPath: keyPath] = nil
        #expect(item.metadata[key] == nil, sourceLocation: sourceLocation)

        item.metadata[key] = "legacy"
        #expect(item[keyPath: keyPath] == "legacy", sourceLocation: sourceLocation)
    }

    // MARK: - AI provenance

    @Test func aiProvenanceUsesLegacyKeys() {
        expectFlag(\.isAIGenerated, storedAs: "isAIGenerated")
        expectFlag(\.isAIEdited, storedAs: "isAIEdited")
        expectFlag(\.hasLLMOverview, storedAs: "hasLLMOverview")
        expectFlag(\.isSummaryGeneratedByAI, storedAs: "summaryGeneratedByAI")
        expectFlag(\.isSummaryReviewPending, storedAs: "summaryReviewPending")
        expectFlag(\.isOverviewReviewPending, storedAs: "overviewReviewPending")
        expectString(\.originalDescription, storedAs: "originalDescription")
    }

    /// Older versions wrote `isLLMGenerated ? "true" : "false"` for this flag.
    @Test func storedFalseReadsAsNotAIGenerated() {
        let item = makeItem()
        item.metadata["isAIGenerated"] = "false"
        #expect(item.isAIGenerated == false)
    }

    // MARK: - Reading

    @Test func summaryUsesLegacyKey() {
        expectString(\.summary, storedAs: "summary")
    }

    @Test func readingProgressStoresThreeDecimals() {
        let item = makeItem()
        #expect(item.readingProgress == 0)

        item.readingProgress = 0.02
        #expect(item.metadata["readingProgress"] == "0.020")
        item.readingProgress = 0.9974
        #expect(item.metadata["readingProgress"] == "0.997")
        item.readingProgress = 1
        #expect(item.metadata["readingProgress"] == "1.000")

        item.metadata["readingProgress"] = "0.250"
        #expect(item.readingProgress == 0.25)
        item.metadata["readingProgress"] = "not a number"
        #expect(item.readingProgress == 0)
    }

    @Test func readTimeMinutesStoresWholeNumber() {
        let item = makeItem()
        #expect(item.readTimeMinutes == nil)

        item.readTimeMinutes = 7
        #expect(item.metadata["readTimeMinutes"] == "7")
        item.readTimeMinutes = nil
        #expect(item.metadata["readTimeMinutes"] == nil)

        item.metadata["readTimeMinutes"] = "12"
        #expect(item.readTimeMinutes == 12)
    }

    // MARK: - Feed

    @Test func feedStateUsesLegacyKeys() {
        expectString(\.feedSourceID, storedAs: "feedSourceID")
        expectFlag(\.isFeedSuggestion, storedAs: "isSuggested")
        expectFlag(\.isFeedIssueRead, storedAs: "feedRead")
    }

    @Test func anyFeedSourceMarksANewsletterIssue() {
        let item = makeItem()
        #expect(item.isNewsletterIssue == false)
        item.metadata["feedSourceID"] = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        #expect(item.isNewsletterIssue == true)
    }

    @Test func publishedAtStoresISO8601() {
        let item = makeItem()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        item.publishedAt = date
        #expect(item.metadata["publishedAt"] == "2023-11-14T22:13:20Z")
        item.publishedAt = nil
        #expect(item.metadata["publishedAt"] == nil)

        item.metadata["publishedAt"] = "2023-11-14T22:13:20Z"
        #expect(item.publishedAt == date)
        item.metadata["publishedAt"] = "yesterday"
        #expect(item.publishedAt == nil)
    }

    @Test func promotionClearsTheStoredSuggestionKeys() {
        let item = makeItem()
        item.metadata["isSuggested"] = "true"
        item.metadata["suggestionDismissed"] = "true"

        item.promoteFromFeedSuggestionIfNeeded()

        #expect(item.metadata["isSuggested"] == nil)
        #expect(item.metadata["suggestionDismissed"] == nil)
        #expect(item.metadata["feedRead"] == "true")
    }

    // MARK: - Video

    @Test func videoStateUsesLegacyKeys() {
        expectString(\.videoSource, storedAs: "videoSource")
        expectString(\.videoID, storedAs: "videoID")
        expectString(\.originalPath, storedAs: "originalPath")
        expectFlag(\.isVideoLocalFile, storedAs: "videoLocalFile")
    }

    @Test func videoDurationStoresOneDecimal() {
        let item = makeItem(type: .video)
        #expect(item.videoDurationSeconds == nil)

        item.videoDurationSeconds = 125
        #expect(item.metadata["videoDuration"] == "125.0")
        item.videoDurationSeconds = 12.34
        #expect(item.metadata["videoDuration"] == "12.3")
        item.videoDurationSeconds = nil
        #expect(item.metadata["videoDuration"] == nil)

        item.metadata["videoDuration"] = "125"
        #expect(item.videoDurationSeconds == 125)
        #expect(item.videoDurationLabel == "2:05")
    }

    @Test func videoDurationLabelIgnoresOtherTypesAndUnusableValues() {
        let article = makeItem(type: .article)
        article.metadata["videoDuration"] = "125.0"
        #expect(article.videoDurationLabel == nil)

        let video = makeItem(type: .video)
        video.metadata["videoDuration"] = "0.4"
        #expect(video.videoDurationLabel == nil)
        video.metadata["videoDuration"] = "inf"
        #expect(video.videoDurationLabel == nil)
    }

    // MARK: - PDF / arXiv

    @Test func documentStateUsesLegacyKeys() {
        expectFlag(\.isPDFCached, storedAs: "pdfCached")
        expectString(\.arxivID, storedAs: "arxivID")
        expectString(\.authors, storedAs: "authors")
    }

    @Test func pdfFormatStoresPDFNotTrue() {
        let item = makeItem()
        #expect(item.isPDFFormat == false)

        item.isPDFFormat = true
        #expect(item.metadata["format"] == "pdf")
        item.isPDFFormat = false
        #expect(item.metadata["format"] == nil)

        item.metadata["format"] = "pdf"
        #expect(item.isPDFFormat == true)
        #expect(item.isPDFDocument == true)
    }

    @Test func pdfDocumentFallsBackToTheURLForOlderItems() {
        let item = makeItem()
        item.sourceURL = "https://example.com/paper.PDF"
        #expect(item.isPDFFormat == false)
        #expect(item.isPDFDocument == true)
    }

    // MARK: - Capture state

    @Test func captureStateUsesLegacyKeys() {
        expectFlag(\.isFetchingMetadata, storedAs: "fetchingMetadata")
        expectFlag(\.isPendingFromExtension, storedAs: "pendingFromExtension")
        expectString(\.thumbnailURL, storedAs: "thumbnailURL")
    }

    // MARK: - Suggestions

    @Test func suggestionStateUsesLegacyKeys() {
        expectFlag(\.isSuggestionDismissed, storedAs: "suggestionDismissed")
        expectString(\.suggestedBoard, storedAs: "suggestedBoard")
        expectString(\.pendingBoardSuggestion, storedAs: "pendingBoardSuggestion")
        expectString(\.suggestedBoardReason, storedAs: "suggestedBoardReason")
    }

    /// The flag stores the opposite of the accessor: "true" means excluded.
    @Test func discussionExclusionIsStoredInverted() {
        let item = makeItem(type: .article)
        #expect(item.isIncludedInDiscussionSuggestions == true)

        item.isIncludedInDiscussionSuggestions = false
        #expect(item.metadata["excludeFromDiscussionSuggestions"] == "true")
        item.isIncludedInDiscussionSuggestions = true
        #expect(item.metadata["excludeFromDiscussionSuggestions"] == nil)

        item.metadata["excludeFromDiscussionSuggestions"] = "true"
        #expect(item.isIncludedInDiscussionSuggestions == false)
    }

    @Test func onlyArticlesCanOptOutOfDiscussionSuggestions() {
        let note = makeItem(type: .note)
        note.isIncludedInDiscussionSuggestions = false
        #expect(note.metadata["excludeFromDiscussionSuggestions"] == nil)

        note.metadata["excludeFromDiscussionSuggestions"] = "true"
        #expect(note.isIncludedInDiscussionSuggestions == true)
    }

    @Test func suggestedBoardModeStoresRawValue() {
        let item = makeItem()
        #expect(item.suggestedBoardMode == nil)

        item.suggestedBoardMode = .existing
        #expect(item.metadata["suggestedBoardMode"] == "existing")
        item.suggestedBoardMode = .create
        #expect(item.metadata["suggestedBoardMode"] == "create")
        item.suggestedBoardMode = nil
        #expect(item.metadata["suggestedBoardMode"] == nil)

        item.metadata["suggestedBoardMode"] = "existing"
        #expect(item.suggestedBoardMode == .existing)
        item.metadata["suggestedBoardMode"] = "unknown"
        #expect(item.suggestedBoardMode == nil)
    }

    @Test func suggestedBoardIDStoresUUIDString() throws {
        let item = makeItem()
        let raw = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        let id = try #require(UUID(uuidString: raw))

        item.suggestedBoardID = id
        #expect(item.metadata["suggestedBoardID"] == raw)
        item.suggestedBoardID = nil
        #expect(item.metadata["suggestedBoardID"] == nil)

        item.metadata["suggestedBoardID"] = raw
        #expect(item.suggestedBoardID == id)
        item.metadata["suggestedBoardID"] = "not-a-uuid"
        #expect(item.suggestedBoardID == nil)
    }

    @Test func suggestedBoardConfidenceStoresTwoDecimals() {
        let item = makeItem()
        #expect(item.suggestedBoardConfidence == nil)

        // Written with the current locale's number format, as it always has been.
        item.suggestedBoardConfidence = 0.914
        #expect(item.metadata["suggestedBoardConfidence"] == "0.91")
        item.suggestedBoardConfidence = nil
        #expect(item.metadata["suggestedBoardConfidence"] == nil)

        item.metadata["suggestedBoardConfidence"] = "0.91"
        #expect(item.suggestedBoardConfidence == 0.91)

        // Written by an older build on a decimal-comma locale.
        item.metadata["suggestedBoardConfidence"] = "0,91"
        #expect(item.suggestedBoardConfidence == 0.91)
    }

    @Test func suggestedBoardAlternativesStoreCommaSeparatedIDs() throws {
        let item = makeItem()
        let rawFirst = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        let rawSecond = "C232AB00-9414-11EC-B3C8-9F6BDECED846"
        let first = try #require(UUID(uuidString: rawFirst))
        let second = try #require(UUID(uuidString: rawSecond))
        #expect(item.suggestedBoardAlternativeIDs.isEmpty)

        item.suggestedBoardAlternativeIDs = [first, second]
        #expect(item.metadata["suggestedBoardAlternatives"] == "\(rawFirst),\(rawSecond)")
        item.suggestedBoardAlternativeIDs = []
        #expect(item.metadata["suggestedBoardAlternatives"] == nil)

        item.metadata["suggestedBoardAlternatives"] = "\(rawSecond),not-a-uuid,\(rawFirst)"
        #expect(item.suggestedBoardAlternativeIDs == [second, first])
    }

    @Test func applyingADecisionWritesTheLegacyDictionary() throws {
        let item = makeItem()
        let rawID = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        let id = try #require(UUID(uuidString: rawID))

        BoardSuggestionMetadata.apply(
            BoardSuggestionDecision(
                suggestedName: "Research",
                mode: .existing,
                recommendedBoardID: id,
                confidence: 0.5,
                reason: "tag overlap",
                alternativeBoardIDs: [id]
            ),
            to: item
        )

        #expect(item.metadata["suggestedBoard"] == "Research")
        #expect(item.metadata["pendingBoardSuggestion"] == "Research")
        #expect(item.metadata["suggestedBoardMode"] == "existing")
        #expect(item.metadata["suggestedBoardID"] == rawID)
        #expect(item.metadata["suggestedBoardReason"] == "tag overlap")
        #expect(item.metadata["suggestedBoardAlternatives"] == rawID)
    }

    @Test func aDecisionReadsBackFromTheLegacyDictionary() throws {
        let item = makeItem()
        let rawID = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        let id = try #require(UUID(uuidString: rawID))
        item.metadata = [
            "suggestedBoard": "Older name",
            "pendingBoardSuggestion": "Research",
            "suggestedBoardMode": "existing",
            "suggestedBoardID": rawID,
            "suggestedBoardConfidence": "0.50",
            "suggestedBoardReason": "tag overlap",
            "suggestedBoardAlternatives": rawID
        ]

        let decision = BoardSuggestionMetadata.decision(from: item)

        #expect(decision == BoardSuggestionDecision(
            suggestedName: "Research",
            mode: .existing,
            recommendedBoardID: id,
            confidence: 0.5,
            reason: "tag overlap",
            alternativeBoardIDs: [id]
        ))
    }

    @Test func applyingASparseDecisionClearsOptionalKeys() {
        let item = makeItem()
        item.metadata["suggestedBoardID"] = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        item.metadata["suggestedBoardReason"] = "stale"
        item.metadata["suggestedBoardAlternatives"] = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"

        BoardSuggestionMetadata.apply(
            BoardSuggestionDecision(
                suggestedName: "New",
                mode: .create,
                recommendedBoardID: nil,
                confidence: 1,
                reason: "",
                alternativeBoardIDs: []
            ),
            to: item
        )

        #expect(item.metadata["suggestedBoardID"] == nil)
        #expect(item.metadata["suggestedBoardReason"] == nil)
        #expect(item.metadata["suggestedBoardAlternatives"] == nil)
    }
}
