import Foundation

/// The strings stored in `Item.metadata`. These are persisted and synced, so a
/// value here must never change: existing items are keyed by these exact bytes.
private enum Key {
    // AI provenance
    static let isAIGenerated = "isAIGenerated"
    static let isAIEdited = "isAIEdited"
    static let hasLLMOverview = "hasLLMOverview"
    static let originalDescription = "originalDescription"
    static let summaryGeneratedByAI = "summaryGeneratedByAI"
    static let summaryReviewPending = "summaryReviewPending"
    static let overviewReviewPending = "overviewReviewPending"

    // Reading
    static let summary = "summary"
    static let readingProgress = "readingProgress"
    static let readTimeMinutes = "readTimeMinutes"

    // Feed
    static let feedSourceID = "feedSourceID"
    static let publishedAt = "publishedAt"
    static let isSuggested = "isSuggested"
    static let feedRead = "feedRead"

    // Video
    static let videoSource = "videoSource"
    static let videoID = "videoID"
    static let videoDuration = "videoDuration"
    static let videoLocalFile = "videoLocalFile"
    static let originalPath = "originalPath"

    // PDF / arXiv
    static let format = "format"
    static let pdfCached = "pdfCached"
    static let arxivID = "arxivID"
    static let authors = "authors"

    // Capture state
    static let fetchingMetadata = "fetchingMetadata"
    static let pendingFromExtension = "pendingFromExtension"
    static let thumbnailURL = "thumbnailURL"

    // Suggestions
    static let suggestionDismissed = "suggestionDismissed"
    static let excludeFromDiscussionSuggestions = "excludeFromDiscussionSuggestions"
    static let suggestedBoard = "suggestedBoard"
    static let pendingBoardSuggestion = "pendingBoardSuggestion"
    static let suggestedBoardMode = "suggestedBoardMode"
    static let suggestedBoardID = "suggestedBoardID"
    static let suggestedBoardConfidence = "suggestedBoardConfidence"
    static let suggestedBoardReason = "suggestedBoardReason"
    static let suggestedBoardAlternatives = "suggestedBoardAlternatives"
}

// Typed access to `Item.metadata`. These are computed over the stored dictionary
// (no schema involvement), and each one keeps the exact stored format so old and
// synced items read back unchanged.
extension Item {
    /// A stored flag: the string "true" when set, the key absent when not.
    /// Anything else reads as false, which covers the "false" some older items
    /// hold for `isAIGenerated`.
    private func flag(_ key: String) -> Bool {
        metadata[key] == "true"
    }

    private func setFlag(_ key: String, _ isOn: Bool) {
        metadata[key] = isOn ? "true" : nil
    }

    // MARK: - AI provenance

    /// Set by older versions on AI-drafted notes; nothing writes it any more,
    /// but those items still show their AI badge.
    var isAIGenerated: Bool {
        get { flag(Key.isAIGenerated) }
        set { setFlag(Key.isAIGenerated, newValue) }
    }

    var isAIEdited: Bool {
        get { flag(Key.isAIEdited) }
        set { setFlag(Key.isAIEdited, newValue) }
    }

    var hasLLMOverview: Bool {
        get { flag(Key.hasLLMOverview) }
        set { setFlag(Key.hasLLMOverview, newValue) }
    }

    /// The text an AI overview replaced, kept so the overview can be reverted.
    var originalDescription: String? {
        get { metadata[Key.originalDescription] }
        set { metadata[Key.originalDescription] = newValue }
    }

    var isSummaryGeneratedByAI: Bool {
        get { flag(Key.summaryGeneratedByAI) }
        set { setFlag(Key.summaryGeneratedByAI, newValue) }
    }

    var isSummaryReviewPending: Bool {
        get { flag(Key.summaryReviewPending) }
        set { setFlag(Key.summaryReviewPending, newValue) }
    }

    var isOverviewReviewPending: Bool {
        get { flag(Key.overviewReviewPending) }
        set { setFlag(Key.overviewReviewPending, newValue) }
    }

    // MARK: - Reading

    /// One-line preview text. Callers trim to their own length before writing.
    var summary: String? {
        get { metadata[Key.summary] }
        set { metadata[Key.summary] = newValue }
    }

    /// Reading position from 0 to 1, stored to three decimals; 0 when unset.
    /// Callers clamp before writing.
    var readingProgress: Double {
        get { Double(metadata[Key.readingProgress] ?? "") ?? 0 }
        set { metadata[Key.readingProgress] = String(format: "%.3f", newValue) }
    }

    var readTimeMinutes: Int? {
        get { metadata[Key.readTimeMinutes].flatMap { Int($0) } }
        set { metadata[Key.readTimeMinutes] = newValue.map { String($0) } }
    }

    // MARK: - Feed / Newsletter

    /// The originating `FeedSource.id` as its `uuidString`.
    var feedSourceID: String? {
        get { metadata[Key.feedSourceID] }
        set { metadata[Key.feedSourceID] = newValue }
    }

    /// Stored as ISO 8601 in UTC. Reads use the format style because the
    /// Following screen parses this for every issue on each render, and a
    /// formatter can't be shared across isolation domains.
    var publishedAt: Date? {
        get { metadata[Key.publishedAt].flatMap { try? Date.ISO8601FormatStyle().parse($0) } }
        set { metadata[Key.publishedAt] = newValue.map { ISO8601DateFormatter().string(from: $0) } }
    }

    /// True for any item that originated from a subscribed feed, regardless
    /// of whether it was later kept into the library.
    var isNewsletterIssue: Bool {
        feedSourceID != nil
    }

    /// True for feed-pipeline items the user has not explicitly kept.
    /// These stay out of inbox triage counts and lists.
    var isFeedSuggestion: Bool {
        get { flag(Key.isSuggested) }
        set { setFlag(Key.isSuggested, newValue) }
    }

    /// Read state for newsletter issues. Opening an issue marks it read.
    var isFeedIssueRead: Bool {
        get { flag(Key.feedRead) }
        set { setFlag(Key.feedRead, newValue) }
    }

    // MARK: - Video

    var videoSource: String? {
        get { metadata[Key.videoSource] }
        set { metadata[Key.videoSource] = newValue }
    }

    var videoID: String? {
        get { metadata[Key.videoID] }
        set { metadata[Key.videoID] = newValue }
    }

    /// Runtime in seconds. Written to one decimal; reads accept any number, so
    /// a whole-number value parses too.
    var videoDurationSeconds: Double? {
        get { metadata[Key.videoDuration].flatMap { Double($0) } }
        set { metadata[Key.videoDuration] = newValue.map { String(format: "%.1f", $0) } }
    }

    /// Runtime of a video item as `m:ss` (or `h:mm:ss`), when its length is
    /// known. Written in seconds — fractional for local files, whole numbers
    /// from a host's oEmbed data — so both forms are parsed as a Double.
    var videoDurationLabel: String? {
        guard type == .video,
              let seconds = videoDurationSeconds,
              seconds.isFinite, seconds >= 1 else { return nil }
        return seconds.formattedTimestamp
    }

    /// True for videos imported from disk by older versions. Nothing creates
    /// these any more, but those items still read this and `originalPath`.
    var isVideoLocalFile: Bool {
        get { flag(Key.videoLocalFile) }
        set { setFlag(Key.videoLocalFile, newValue) }
    }

    var originalPath: String? {
        get { metadata[Key.originalPath] }
        set { metadata[Key.originalPath] = newValue }
    }

    // MARK: - PDF / arXiv

    /// Whether capture or enrichment recorded this item's format as PDF.
    /// `isPDFDocument` is the wider question and also checks the URL.
    var isPDFFormat: Bool {
        get { metadata[Key.format] == "pdf" }
        set { metadata[Key.format] = newValue ? "pdf" : nil }
    }

    /// True when what this item points at is a PDF rather than a web page.
    ///
    /// The capture path and the metadata enricher both record the format
    /// explicitly; the URL check is the fallback for items saved before they
    /// did, so a legacy `.pdf` link still opens in the document reader.
    var isPDFDocument: Bool {
        if isPDFFormat { return true }
        guard let url = resolvedSourceURL(from: sourceURL) else { return false }
        return url.pathExtension.lowercased() == "pdf"
    }

    var isPDFCached: Bool {
        get { flag(Key.pdfCached) }
        set { setFlag(Key.pdfCached, newValue) }
    }

    var arxivID: String? {
        get { metadata[Key.arxivID] }
        set { metadata[Key.arxivID] = newValue }
    }

    /// Display-ready author line, comma-separated when there are several.
    var authors: String? {
        get { metadata[Key.authors] }
        set { metadata[Key.authors] = newValue }
    }

    // MARK: - Capture state

    /// True while enrichment is in flight; drives the loading state.
    var isFetchingMetadata: Bool {
        get { flag(Key.fetchingMetadata) }
        set { setFlag(Key.fetchingMetadata, newValue) }
    }

    /// True for items the Share Extension saved that the app has not drained.
    var isPendingFromExtension: Bool {
        get { flag(Key.pendingFromExtension) }
        set { setFlag(Key.pendingFromExtension, newValue) }
    }

    var thumbnailURL: String? {
        get { metadata[Key.thumbnailURL] }
        set { metadata[Key.thumbnailURL] = newValue }
    }

    // MARK: - Suggestions

    var isSuggestionDismissed: Bool {
        get { flag(Key.suggestionDismissed) }
        set { setFlag(Key.suggestionDismissed, newValue) }
    }

    /// Whether this item should be considered by discussion suggestion generation.
    /// Only article items can opt out; all other types are always included.
    var isIncludedInDiscussionSuggestions: Bool {
        get {
            guard type == .article else { return true }
            return !flag(Key.excludeFromDiscussionSuggestions)
        }
        set {
            guard type == .article else { return }
            setFlag(Key.excludeFromDiscussionSuggestions, !newValue)
        }
    }

    /// The last suggested board name. Outlives `pendingBoardSuggestion`, which
    /// is cleared once the suggestion is resolved.
    var suggestedBoard: String? {
        get { metadata[Key.suggestedBoard] }
        set { metadata[Key.suggestedBoard] = newValue }
    }

    var pendingBoardSuggestion: String? {
        get { metadata[Key.pendingBoardSuggestion] }
        set { metadata[Key.pendingBoardSuggestion] = newValue }
    }

    var suggestedBoardMode: BoardSuggestionMode? {
        get { metadata[Key.suggestedBoardMode].flatMap { BoardSuggestionMode(rawValue: $0) } }
        set { metadata[Key.suggestedBoardMode] = newValue?.rawValue }
    }

    var suggestedBoardID: UUID? {
        get { metadata[Key.suggestedBoardID].flatMap { UUID(uuidString: $0) } }
        set { metadata[Key.suggestedBoardID] = newValue?.uuidString }
    }

    var suggestedBoardConfidence: Double? {
        // Older builds wrote this in the user's locale, so a stored value may use a decimal comma.
        get {
            metadata[Key.suggestedBoardConfidence].flatMap {
                Double($0.replacingOccurrences(of: ",", with: "."))
            }
        }
        set {
            metadata[Key.suggestedBoardConfidence] = newValue.map { String(format: "%.2f", $0) }
        }
    }

    var suggestedBoardReason: String? {
        get { metadata[Key.suggestedBoardReason] }
        set { metadata[Key.suggestedBoardReason] = newValue }
    }

    /// Stored comma-separated. An empty list removes the key.
    var suggestedBoardAlternativeIDs: [UUID] {
        get { BoardSuggestionMetadata.parseAlternativeIDs(metadata[Key.suggestedBoardAlternatives]) }
        set {
            metadata[Key.suggestedBoardAlternatives] = newValue.isEmpty
                ? nil
                : newValue.map(\.uuidString).joined(separator: ",")
        }
    }
}
