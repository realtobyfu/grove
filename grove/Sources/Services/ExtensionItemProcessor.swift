import SwiftData
import Foundation

/// Processes items saved by the Share Extension on main app launch.
///
/// The Share Extension writes Items directly to the shared ModelContainer
/// but defers heavy processing (metadata fetch, auto-tagging) to the main
/// app to stay within the extension's 120 MB memory limit. This processor
/// runs once on launch and handles all deferred work.
@MainActor
enum ExtensionItemProcessor {

    /// Finds items marked with `pendingFromExtension` and runs the deferred
    /// processing pipeline: metadata fetch (for URLs) and auto-tagging.
    ///
    /// Safe to call on every launch — returns immediately if no pending items.
    static func processIfNeeded(
        context: ModelContext,
        metadataFetcher: URLMetadataFetcherProtocol = URLMetadataFetcher.shared,
        imageDownloader: ImageDownloadServiceProtocol = ImageDownloadService.shared,
        autoTagService: AutoTagServiceProtocol = AutoTagService()
    ) {
        let descriptor = FetchDescriptor<Item>()
        guard let items = try? context.fetch(descriptor) else { return }

        let pending = items.filter { $0.isPendingFromExtension }
        guard !pending.isEmpty else { return }

        let enricher = ItemMetadataEnricher(
            metadataFetcher: metadataFetcher,
            imageDownloader: imageDownloader
        )

        for item in pending {
            // Clear the extension flag immediately to avoid reprocessing
            item.isPendingFromExtension = false

            // Dedupe: the Share Extension can't run the main app's URL dedupe, so
            // reconcile here — if this URL already exists as a reachable item,
            // drop the duplicate the extension created.
            if let urlString = item.sourceURL,
               duplicateExists(of: urlString, excluding: item.id, in: items) {
                context.delete(item)
                continue
            }

            // The extension saves every URL as a plain `.article` with no routing
            // metadata. Classify it here, before enrichment, so the drain produces
            // exactly what in-app capture would have.
            if let urlString = item.sourceURL, isWebURL(urlString) {
                CaptureService.applyURLClassification(item: item, urlString: urlString)
            }

            let itemID = item.id
            let sourceURL = item.sourceURL
            let needsMetadata = item.isFetchingMetadata

            Task {
                // Step 1: Enrich URL items through the same router in-app capture
                // uses — arXiv, video oEmbed, PDF, or the generic scrape.
                if needsMetadata, let urlString = sourceURL {
                    _ = await enricher.enrichURLItem(
                        itemID: itemID,
                        urlString: urlString,
                        context: context
                    )
                }

                // Step 2: Auto-tag with LLM (runs after metadata so LLM has full context)
                await autoTag(itemID: itemID, context: context, autoTagService: autoTagService)
            }
        }

        try? context.save()
    }

    /// Whether a reachable (non-pending, non-dismissed/archived) item already
    /// has the same normalized source URL.
    private static func duplicateExists(of urlString: String, excluding id: UUID, in items: [Item]) -> Bool {
        let normalized = CaptureService.normalizedURLString(urlString)
        return items.contains { other in
            guard other.id != id,
                  !other.isPendingFromExtension,
                  !other.isSuggestionDismissed,
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
    private static func autoTag(itemID: UUID, context: ModelContext, autoTagService: AutoTagServiceProtocol) async {
        guard LLMServiceConfig.isConfigured else { return }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else { return }

        await autoTagService.tagItem(item, in: context)
    }
}
