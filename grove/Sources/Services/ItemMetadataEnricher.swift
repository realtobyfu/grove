import Foundation
import SwiftData

/// Handles metadata fetching, thumbnail download, and LLM overview generation for Items.
/// Extracted from CaptureService to isolate enrichment responsibilities.
@MainActor
@Observable
final class ItemMetadataEnricher {
    private let metadataFetcher: URLMetadataFetcherProtocol
    private let imageDownloader: ImageDownloadServiceProtocol

    init(
        metadataFetcher: URLMetadataFetcherProtocol = URLMetadataFetcher.shared,
        imageDownloader: ImageDownloadServiceProtocol = ImageDownloadService.shared
    ) {
        self.metadataFetcher = metadataFetcher
        self.imageDownloader = imageDownloader
    }

    /// Fetches URL metadata and updates the item in the given context.
    /// Returns the fetched metadata title and description for downstream use.
    func enrichURLItem(
        itemID: UUID,
        urlString: String,
        context: ModelContext
    ) async -> (title: String?, description: String?, bodyText: String?) {
        guard let metadata = await metadataFetcher.fetch(urlString: urlString) else {
            // Clear loading flag even on failure
            let desc = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            if let fetchedItem = try? context.fetch(desc).first {
                fetchedItem.metadata["fetchingMetadata"] = nil
                try? context.save()
            }
            return (nil, nil, nil)
        }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let fetchedItem = try? context.fetch(descriptor).first else {
            return (metadata.title, metadata.description, metadata.bodyText)
        }

        if let title = metadata.title {
            fetchedItem.title = title
        }
        if let description = metadata.description {
            fetchedItem.content = description
        }

        // Prefer LP image data (works on bot-protected sites), fall back to URL download
        if let rawImageData = metadata.imageData,
           let compressed = imageDownloader.compressImageData(rawImageData) {
            fetchedItem.thumbnail = compressed
        } else if let imageURLString = metadata.imageURL {
            fetchedItem.metadata["thumbnailURL"] = imageURLString
            if let imageData = await imageDownloader.downloadAndCompress(urlString: imageURLString) {
                fetchedItem.thumbnail = imageData
            }
        }

        fetchedItem.metadata["fetchingMetadata"] = nil
        fetchedItem.updatedAt = .now
        try? context.save()

        return (metadata.title, metadata.description, metadata.bodyText)
    }

    /// Generates a multi-paragraph overview/summary for an article using the LLM.
    /// Stores the result in item.content, replacing the short OG description.
    func generateOverview(
        itemID: UUID,
        context: ModelContext,
        title: String,
        description: String?,
        bodyText: String?
    ) async {
        guard LLMServiceConfig.isConfigured else { return }

        let sourceText = bodyText ?? description ?? ""
        guard sourceText.count > 20 else { return }

        let systemPrompt = """
        You are a knowledge-management assistant. Given an article's title and text, \
        write a concise overview (2-3 short paragraphs) that captures the key ideas, \
        arguments, and takeaways. Write in plain prose, no bullet points or headers. \
        Return only the overview text, nothing else.
        """

        let userPrompt = """
        Title: \(title)

        Article text:
        \(String(sourceText.prefix(4000)))
        """

        let provider = LLMServiceConfig.makeProvider()
        guard let result = await provider.complete(
            system: systemPrompt,
            user: userPrompt,
            service: "overview"
        ) else { return }

        let overview = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !overview.isEmpty else { return }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else { return }

        if let original = item.content, !original.isEmpty {
            item.metadata["originalDescription"] = original
        }
        item.content = overview
        item.metadata["hasLLMOverview"] = "true"
        item.metadata["overviewReviewPending"] = "true"
        item.updatedAt = .now
        try? context.save()
    }

    /// After metadata enrichment, extract a summary fallback from the overview if needed.
    func extractSummaryFallback(
        itemID: UUID,
        context: ModelContext
    ) {
        let desc = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(desc).first,
              item.metadata["summary"] == nil,
              let overviewContent = item.content, !overviewContent.isEmpty else { return }

        let firstSentence = overviewContent
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !firstSentence.isEmpty {
            item.metadata["summary"] = String(firstSentence.prefix(120))
            try? context.save()
        }
    }

    /// Mark summary review as pending if summary was generated.
    func markSummaryReviewIfNeeded(
        itemID: UUID,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first,
              item.metadata["summary"] != nil else { return }
        item.metadata["summaryReviewPending"] = "true"
        try? context.save()
    }
}
