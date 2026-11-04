import Foundation
import SQLiteData

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
        let host: ItemGraph
        /// True when this call created a new library item — the only case
        /// worth confirming in the UI.
        let didCapture: Bool
    }

    /// The item a new reflection or highlight should attach to. Returns
    /// `readerItem` unless the reader has navigated to a different page, in
    /// which case that page is captured into the library and returned.
    static func host(
        for readerItem: ItemGraph,
        navigatedURL: URL?,
        database: any DatabaseWriter = AppDatabase.current
    ) -> Resolution {
        guard let navigatedURL,
              isDifferentPage(navigatedURL, from: readerItem)
        else { return Resolution(host: readerItem, didCapture: false) }

        let (captured, isDuplicate) = capturePage(navigatedURL, readFrom: readerItem.id, database: database)
        return Resolution(host: captured, didCapture: !isDuplicate)
    }

    /// Saves a page encountered while reading into the library. Used both by
    /// capture-on-write and by the reader's explicit save button. The page
    /// lands unfiled and active — a deliberate save, not a triage candidate.
    @discardableResult
    static func capturePage(
        _ url: URL,
        readFrom readerItemID: Item.ID?,
        database: any DatabaseWriter = AppDatabase.current
    ) -> (item: ItemGraph, isDuplicate: Bool) {
        let capture = CaptureService(database: database)
        let (captured, isDuplicate) = capture.captureItemDetailed(input: url.absoluteString)
        let graph = database.attempt { db -> ItemGraph? in
            if captured.status == .inbox {
                try Item.modify(captured.id, in: db) { $0.status = .active }
            }
            if let readerItemID {
                // Harvesting a link counts as having processed the source issue.
                if let readerItem = try Item.find(readerItemID).fetchOne(db),
                   readerItem.isNewsletterIssue, !readerItem.isFeedIssueRead {
                    try Item.modify(readerItemID, in: db) { $0.isFeedIssueRead = true }
                }
                try recordProvenance(from: readerItemID, to: captured.id, in: db)
            }
            return try ItemGraph.fetch(captured.id, in: db)
        }
        return ((graph ?? nil) ?? ItemGraph(item: captured), isDuplicate)
    }

    // MARK: - Provenance

    /// The connection type that records "I got here from there". Kept apart
    /// from `.related` so a trail followed while reading can be told from a
    /// link the user wrote by hand.
    static let provenanceType: ConnectionType = .linkedFrom

    /// Records that `targetID` was reached by following a link while reading
    /// `sourceID`.
    ///
    /// At most one edge per ordered pair: if the two are already connected in
    /// this direction — by a wiki-link, the inspector, chat, or an earlier
    /// visit — nothing is written. A trail is also never recorded back down one
    /// that already exists, so two items that link to each other (a series, a
    /// reply) don't end up each claiming to have come from the other.
    @discardableResult
    static func recordProvenance(
        from sourceID: Item.ID,
        to targetID: Item.ID,
        database: any DatabaseWriter = AppDatabase.current
    ) -> Connection? {
        database.attempt { db in
            try recordProvenance(from: sourceID, to: targetID, in: db)
        } ?? nil
    }

    /// Checks the database rather than a graph the caller holds: the reader
    /// runs this on every navigation, and a snapshot from before the last one
    /// would record the same edge twice.
    @discardableResult
    private static func recordProvenance(
        from sourceID: Item.ID,
        to targetID: Item.ID,
        in db: Database
    ) throws -> Connection? {
        guard sourceID != targetID else { return nil }
        // The reader can outlive the item it opened. A connection to a deleted
        // item fails its foreign key, and with it the caller's whole transaction.
        let endpoints = try Item.where { $0.id.in([sourceID, targetID]) }.fetchCount(db)
        guard endpoints == 2 else { return nil }
        let existingEdges = try Connection
            .where { $0.sourceItemID.eq(sourceID) && $0.targetItemID.eq(targetID) }
            .fetchCount(db)
        guard existingEdges == 0 else { return nil }
        let type = provenanceType
        let reverseTrails = try Connection
            .where { $0.sourceItemID.eq(targetID) && $0.targetItemID.eq(sourceID) && $0.type.eq(type) }
            .fetchCount(db)
        guard reverseTrails == 0 else { return nil }

        let connection = Connection(sourceItemID: sourceID, targetItemID: targetID, type: type)
        try Connection.insert { connection }.execute(db)
        for itemID in [sourceID, targetID] {
            try Item.modify(itemID, in: db) { $0.updatedAt = .now }
        }
        return connection
    }

    /// The item this one was most recently reached from while reading, or nil
    /// when it was never harvested from another page.
    static func provenanceSource(of item: ItemGraph) -> Item? {
        item.incomingConnections
            .filter { $0.type == provenanceType }
            .max { $0.createdAt < $1.createdAt }?
            .sourceItem
    }

    /// Whether `url` is a different page than the item's own source.
    static func isDifferentPage(_ url: URL, from item: ItemGraph) -> Bool {
        guard let ownURL = item.sourceURL else { return true }
        return CaptureService.normalizedURLString(url.absoluteString)
            != CaptureService.normalizedURLString(ownURL)
    }

    /// Writing is keeping: promote a feed suggestion into the library and
    /// backfill real content (page metadata + an LLM overview) for issues
    /// that only ever carried a feed excerpt.
    static func promoteAfterWriting(
        _ hostID: Item.ID,
        database: any DatabaseWriter = AppDatabase.current
    ) {
        let promoted = database.attempt { db -> Item? in
            guard let host = try Item.find(hostID).fetchOne(db), host.isFeedSuggestion else { return nil }
            return try Item.modify(hostID, in: db) { $0.promoteFromFeedSuggestionIfNeeded() }
        } ?? nil
        guard let promoted,
              (promoted.content ?? "").isEmpty,
              let urlString = promoted.sourceURL else { return }
        Task {
            await ItemMetadataEnricher(database: database).enrichPromotedIssue(
                itemID: hostID,
                urlString: urlString
            )
        }
    }
}
