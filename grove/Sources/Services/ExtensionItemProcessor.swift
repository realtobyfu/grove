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

        let pending = items.filter { $0.metadata["pendingFromExtension"] == "true" }
        guard !pending.isEmpty else { return }

        for item in pending {
            // Clear the extension flag immediately to avoid reprocessing
            item.metadata["pendingFromExtension"] = nil

            // Dedupe: the Share Extension can't run the main app's URL dedupe, so
            // reconcile here — if this URL already exists as a reachable item,
            // drop the duplicate the extension created.
            if let urlString = item.sourceURL,
               duplicateExists(of: urlString, excluding: item.id, in: items) {
                context.delete(item)
                continue
            }

            let itemID = item.id
            let sourceURL = item.sourceURL
            let needsMetadata = item.metadata["fetchingMetadata"] == "true"

            Task {
                // Step 1: Fetch metadata for URL items (title, description, thumbnail)
                if needsMetadata, let urlString = sourceURL {
                    await fetchMetadata(
                        itemID: itemID,
                        urlString: urlString,
                        context: context,
                        metadataFetcher: metadataFetcher,
                        imageDownloader: imageDownloader
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
                  other.metadata["pendingFromExtension"] != "true",
                  other.metadata["suggestionDismissed"] != "true",
                  other.status != .dismissed, other.status != .archived,
                  let source = other.sourceURL else { return false }
            return CaptureService.normalizedURLString(source) == normalized
        }
    }

    // MARK: - Metadata Fetch

    /// Fetches URL metadata (title, description, thumbnail) and updates the item.
    /// Same pipeline as CaptureService but for pre-existing items.
    private static func fetchMetadata(
        itemID: UUID,
        urlString: String,
        context: ModelContext,
        metadataFetcher: URLMetadataFetcherProtocol,
        imageDownloader: ImageDownloadServiceProtocol
    ) async {
        guard let metadata = await metadataFetcher.fetch(urlString: urlString) else {
            // Clear loading flag even on failure
            let desc = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            if let item = try? context.fetch(desc).first {
                item.metadata["fetchingMetadata"] = nil
                try? context.save()
            }
            return
        }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else { return }

        if let title = metadata.title {
            item.title = title
        }
        if let description = metadata.description {
            item.content = description
        }

        // Prefer LinkPresentation image data, fall back to URL download
        if let rawImageData = metadata.imageData,
           let compressed = imageDownloader.compressImageData(rawImageData) {
            item.thumbnail = compressed
        } else if let imageURLString = metadata.imageURL {
            item.metadata["thumbnailURL"] = imageURLString
            if let imageData = await imageDownloader.downloadAndCompress(urlString: imageURLString) {
                item.thumbnail = imageData
            }
        }

        item.metadata["fetchingMetadata"] = nil
        item.updatedAt = .now
        try? context.save()
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
