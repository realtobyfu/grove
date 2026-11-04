import SQLiteData
import Foundation

/// Processes items saved by the Share Extension on main app launch.
///
/// The Share Extension writes Items directly to the shared database
/// but defers heavy processing (metadata fetch, auto-tagging) to the main
/// app to stay within the extension's 120 MB memory limit. This processor
/// runs once on launch and handles all deferred work.
@MainActor
enum ExtensionItemProcessor {

    /// An item that survived dedupe and is waiting on the async pipeline.
    private struct ClaimedItem {
        let id: Item.ID
        let sourceURL: String?
        let needsMetadata: Bool
    }

    /// Finds items marked with `pendingFromExtension` and runs the deferred
    /// processing pipeline: metadata fetch (for URLs) and auto-tagging.
    ///
    /// Safe to call on every launch — returns immediately if no pending items.
    static func processIfNeeded(
        database: any DatabaseWriter = AppDatabase.current,
        metadataFetcher: URLMetadataFetcherProtocol = URLMetadataFetcher.shared,
        imageDownloader: ImageDownloadServiceProtocol = ImageDownloadService.shared,
        autoTagService: AutoTagServiceProtocol? = nil
    ) {
        let claimed = database.attempt { db -> [ClaimedItem] in
            // Each pending item is updated in this array as well as the database,
            // so the duplicate check below sees the ones already processed: two
            // shares of one URL in the same batch leave a single item.
            var items = try Item.all.fetchAll(db)
            var claimed: [ClaimedItem] = []

            for index in items.indices where items[index].metadata["pendingFromExtension"] == "true" {
                // Clear the extension flag immediately to avoid reprocessing
                items[index].metadata["pendingFromExtension"] = nil

                // Dedupe: the Share Extension can't run the main app's URL dedupe, so
                // reconcile here — if this URL already exists as a reachable item,
                // drop the duplicate the extension created.
                if let urlString = items[index].sourceURL,
                   duplicateExists(of: urlString, excluding: items[index].id, in: items) {
                    try Item.find(items[index].id).delete().execute(db)
                    continue
                }

                // The extension saves every URL as a plain `.article` with no routing
                // metadata. Classify it here, before enrichment, so the drain produces
                // exactly what in-app capture would have.
                if let urlString = items[index].sourceURL, isWebURL(urlString) {
                    CaptureService.applyURLClassification(item: &items[index], urlString: urlString)
                }

                let row = items[index]
                try Item.update(row).execute(db)
                claimed.append(ClaimedItem(
                    id: row.id,
                    sourceURL: row.sourceURL,
                    needsMetadata: row.metadata["fetchingMetadata"] == "true"
                ))
            }

            return claimed
        }
        guard let claimed, !claimed.isEmpty else { return }

        let enricher = ItemMetadataEnricher(
            database: database,
            metadataFetcher: metadataFetcher,
            imageDownloader: imageDownloader
        )
        let autoTagService = autoTagService ?? AutoTagService(database: database)

        for item in claimed {
            Task {
                // Step 1: Enrich URL items through the same router in-app capture
                // uses — arXiv, video oEmbed, PDF, or the generic scrape.
                if item.needsMetadata, let urlString = item.sourceURL {
                    _ = await enricher.enrichURLItem(
                        itemID: item.id,
                        urlString: urlString
                    )
                }

                // Step 2: Auto-tag with LLM (runs after metadata so LLM has full context)
                await autoTag(itemID: item.id, autoTagService: autoTagService)
            }
        }
    }

    /// Whether a reachable (non-pending, non-dismissed/archived) item already
    /// has the same normalized source URL.
    private static func duplicateExists(of urlString: String, excluding id: UUID, in items: [Item]) -> Bool {
        let normalized = CaptureService.normalizedURLString(urlString)
        return items.contains { other in
            guard other.id != id,
                  other.metadata["pendingFromExtension"] != "true",
                  other.metadata["suggestionDismissed"] != "true",
                  other.status != .dismissed, other.status != .archived,
                  let source = other.sourceURL else { return false }
            return CaptureService.normalizedURLString(source) == normalized
        }
    }

    /// Only http(s) URLs get classified — a local-file or custom-scheme source
    /// isn't a web page and has no type to derive.
    private static func isWebURL(_ urlString: String) -> Bool {
        guard let scheme = URL(string: urlString)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    // MARK: - Auto-Tagging

    /// Runs LLM auto-tagging on the item if AI is configured.
    private static func autoTag(itemID: UUID, autoTagService: AutoTagServiceProtocol) async {
        guard LLMServiceConfig.isConfigured else { return }

        await autoTagService.tagItem(itemID)
    }
}
