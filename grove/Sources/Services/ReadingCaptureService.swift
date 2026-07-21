import Foundation
import SwiftData

/// Capture-on-write for in-reader browsing.
///
/// Reading inside Grove wanders: a newsletter issue links to an article,
/// that article links onward. Those pages stay ephemeral until the reader
/// writes something — at which point the page becomes a real library item
/// so the note has somewhere durable to live. Shared by the macOS reader
/// panel and the iOS reader so the two can't drift.
@MainActor
enum ReadingCapture {
    struct Resolution {
        let host: Item
        /// True when this call created a new library item — the only case
        /// worth confirming in the UI.
        let didCapture: Bool
    }

    /// The item a new reflection or highlight should attach to. Returns
    /// `readerItem` unless the reader has navigated to a different page, in
    /// which case that page is captured into the library and returned.
    static func host(
        for readerItem: Item,
        navigatedURL: URL?,
        in context: ModelContext
    ) -> Resolution {
        guard let navigatedURL,
              isDifferentPage(navigatedURL, from: readerItem)
        else { return Resolution(host: readerItem, didCapture: false) }

        let (captured, isDuplicate) = capturePage(navigatedURL, readFrom: readerItem, in: context)
        return Resolution(host: captured, didCapture: !isDuplicate)
    }

    /// Saves a page encountered while reading into the library. Used both by
    /// capture-on-write and by the reader's explicit save button. The page
    /// lands unfiled and active — a deliberate save, not a triage candidate.
    @discardableResult
    static func capturePage(
        _ url: URL,
        readFrom readerItem: Item?,
        in context: ModelContext
    ) -> (item: Item, isDuplicate: Bool) {
        let capture = CaptureService(modelContext: context)
        let (captured, isDuplicate) = capture.captureItemDetailed(input: url.absoluteString)
        if captured.status == .inbox {
            captured.status = .active
        }
        // Harvesting a link counts as having processed the source issue.
        if let readerItem, readerItem.isNewsletterIssue {
            readerItem.isFeedIssueRead = true
        }
        try? context.save()
        return (captured, isDuplicate)
    }

    /// Whether `url` is a different page than the item's own source.
    static func isDifferentPage(_ url: URL, from item: Item) -> Bool {
        guard let ownURL = item.sourceURL else { return true }
        return CaptureService.normalizedURLString(url.absoluteString)
            != CaptureService.normalizedURLString(ownURL)
    }

    /// Writing is keeping: promote a feed suggestion into the library and
    /// backfill real content (page metadata + an LLM overview) for issues
    /// that only ever carried a feed excerpt.
    static func promoteAfterWriting(_ host: Item, in context: ModelContext) {
        let wasSuggestion = host.isFeedSuggestion
        host.promoteFromFeedSuggestionIfNeeded()
        guard wasSuggestion,
              (host.content ?? "").isEmpty,
              let urlString = host.sourceURL else { return }
        let hostID = host.id
        Task {
            await ItemMetadataEnricher().enrichPromotedIssue(
                itemID: hostID,
                urlString: urlString,
                context: context
            )
        }
    }
}
