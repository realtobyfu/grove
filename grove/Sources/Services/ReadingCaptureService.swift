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
        if let readerItem {
            recordProvenance(from: readerItem, to: captured, in: context)
        }
        return (captured, isDuplicate)
    }

    // MARK: - Provenance

    /// The connection type that records "I got here from there". Kept apart
    /// from `.related` so a trail followed while reading can be told from a
    /// link the user wrote by hand.
    static let provenanceType: ConnectionType = .linkedFrom

    /// Records that `target` was reached by following a link while reading
    /// `source`.
    ///
    /// At most one edge per ordered pair: if the two are already connected in
    /// this direction — by a wiki-link, the inspector, chat, or an earlier
    /// visit — nothing is written. A trail is also never recorded back down one
    /// that already exists, so two items that link to each other (a series, a
    /// reply) don't end up each claiming to have come from the other.
    @discardableResult
    static func recordProvenance(
        from source: Item,
        to target: Item,
        in context: ModelContext
    ) -> Connection? {
        guard source.id != target.id else { return nil }
        guard !source.outgoingConnections.contains(where: { $0.targetItem?.id == target.id })
        else { return nil }
        guard !source.incomingConnections.contains(where: {
            $0.type == provenanceType && $0.sourceItem?.id == target.id
        }) else { return nil }

        let connection = Connection(sourceItem: source, targetItem: target, type: provenanceType)
        context.insert(connection)
        source.outgoingConnections.append(connection)
        target.incomingConnections.append(connection)
        source.updatedAt = .now
        target.updatedAt = .now
        try? context.save()
        return connection
    }

    /// The item this one was most recently reached from while reading, or nil
    /// when it was never harvested from another page.
    static func provenanceSource(of item: Item) -> Item? {
        item.incomingConnections
            .filter { $0.type == provenanceType }
            .max { $0.createdAt < $1.createdAt }?
            .sourceItem
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
