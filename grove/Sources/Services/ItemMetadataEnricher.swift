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
    ///
    /// Sources that publish structured metadata get a dedicated path — arXiv's
    /// Atom API, oEmbed for video, the PDF document itself — because scraping
    /// their HTML yields either nothing or the wrong thing. Every specialized
    /// path falls back to the generic scrape if it comes up empty.
    func enrichURLItem(
        itemID: UUID,
        urlString: String,
        context: ModelContext
    ) async -> (title: String?, description: String?, bodyText: String?) {
        let routing = routingInfo(itemID: itemID, context: context)

        if let arxivID = routing.arxivID,
           let result = await enrichArxivItem(itemID: itemID, arxivID: arxivID, context: context) {
            return result
        } else if routing.isVideo,
                  let source = routing.videoSource,
                  let videoID = routing.videoID,
                  let result = await enrichVideoItem(
                      itemID: itemID,
                      source: source,
                      videoID: videoID,
                      urlString: urlString,
                      context: context
                  ) {
            return result
        } else if routing.isPDF,
                  let result = await enrichPDFItem(itemID: itemID, urlString: urlString, context: context) {
            return result
        }

        return await enrichGenericURLItem(itemID: itemID, urlString: urlString, context: context)
    }

    private struct EnrichmentRouting {
        var arxivID: String?
        var videoSource: String?
        var videoID: String?
        var isVideo = false
        var isPDF = false
    }

    private func routingInfo(itemID: UUID, context: ModelContext) -> EnrichmentRouting {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else { return EnrichmentRouting() }
        return EnrichmentRouting(
            arxivID: item.arxivID,
            videoSource: item.videoSource,
            videoID: item.videoID,
            isVideo: item.type == .video,
            isPDF: item.isPDFFormat
        )
    }

    /// Clears the loading flag so a failed fetch doesn't leave a permanent spinner.
    private func finishFetching(itemID: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else { return }
        item.isFetchingMetadata = false
        item.updatedAt = .now
        try? context.save()
    }

    // MARK: - arXiv

    private func enrichArxivItem(
        itemID: UUID,
        arxivID: String,
        context: ModelContext
    ) async -> (title: String?, description: String?, bodyText: String?)? {
        guard let paper = await ArxivMetadataService.fetch(arxivID: arxivID) else { return nil }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else {
            return (paper.title, paper.summary, paper.summary)
        }

        item.title = paper.title
        if !paper.summary.isEmpty {
            item.content = paper.summary
        }
        if !paper.authors.isEmpty {
            item.authors = paper.authors.joined(separator: ", ")
        }
        item.isFetchingMetadata = false
        item.updatedAt = .now
        try? context.save()

        return (paper.title, paper.summary.isEmpty ? nil : paper.summary, paper.summary.isEmpty ? nil : paper.summary)
    }

    // MARK: - Video (oEmbed)

    /// oEmbed gives the authoritative title, channel, and thumbnail; it gives
    /// nothing else. The page scrape runs alongside it for the description,
    /// body text, and — on YouTube, whose oEmbed omits it — the runtime. Both
    /// requests go out at once so the video path is no slower than the generic
    /// one it replaces.
    private func enrichVideoItem(
        itemID: UUID,
        source: String,
        videoID: String,
        urlString: String,
        context: ModelContext
    ) async -> (title: String?, description: String?, bodyText: String?)? {
        // Bound to a local so the child task captures the Sendable fetcher
        // rather than this @MainActor-isolated object.
        let fetcher = metadataFetcher
        async let oembedFetch = OEmbedService.fetch(
            source: source,
            videoID: videoID,
            originalURL: urlString
        )
        async let scrapeFetch = fetcher.fetch(urlString: urlString)

        let oembed = await oembedFetch
        let scraped = await scrapeFetch

        let oembedTitle = oembed?.title.flatMap { $0.isEmpty ? nil : $0 }
        let title = oembedTitle ?? scraped?.title
        let thumbnailURL = oembed?.thumbnailURL ?? scraped?.imageURL
        let description = scraped?.description

        // Nothing usable from either source is no better than a failure — let
        // the generic scrape have a turn.
        guard title?.isEmpty == false || thumbnailURL != nil || description?.isEmpty == false else {
            return nil
        }

        var thumbnailData: Data?
        if let thumbnailURL {
            thumbnailData = await imageDownloader.downloadAndCompress(urlString: thumbnailURL)
        }
        if thumbnailData == nil, let rawImageData = scraped?.imageData {
            thumbnailData = imageDownloader.compressImageData(rawImageData)
        }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else {
            return (title, description, scraped?.bodyText)
        }

        if let title, !title.isEmpty {
            item.title = title
        }
        if let description, !description.isEmpty {
            item.content = description
        }
        if let author = oembed?.authorName, !author.isEmpty {
            item.authors = author
        }
        if let thumbnailURL {
            item.thumbnailURL = thumbnailURL
        }
        if let thumbnailData {
            item.thumbnail = thumbnailData
        }
        if let duration = oembed?.duration ?? scraped?.durationSeconds {
            // Same format the local-video importer writes.
            item.videoDurationSeconds = Double(duration)
        }
        item.isFetchingMetadata = false
        item.updatedAt = .now
        try? context.save()

        return (title, description, scraped?.bodyText)
    }

    // MARK: - PDF

    private func enrichPDFItem(
        itemID: UUID,
        urlString: String,
        context: ModelContext
    ) async -> (title: String?, description: String?, bodyText: String?)? {
        guard let url = URL(string: urlString) else { return nil }

        // Record the format even if the download later fails: the URL is a PDF
        // either way, and the reader routes on this key.
        markPDFFormat(itemID: itemID, context: context)

        guard let extracted = await PDFMetadataService.downloadAndExtract(
            url: url,
            itemID: itemID
        ) else { return nil }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else {
            return (extracted.title, nil, nil)
        }

        if let title = extracted.title, !title.isEmpty {
            item.title = title
        }
        if let author = extracted.author, !author.isEmpty {
            item.authors = author
        }
        if let thumbnailData = extracted.thumbnailData {
            item.thumbnail = thumbnailData
        }
        item.isPDFCached = true
        item.isFetchingMetadata = false
        item.updatedAt = .now
        try? context.save()

        return (extracted.title, nil, nil)
    }

    private func markPDFFormat(itemID: UUID, context: ModelContext) {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else { return }
        item.isPDFFormat = true
        try? context.save()
    }

    // MARK: - Generic

    private func enrichGenericURLItem(
        itemID: UUID,
        urlString: String,
        context: ModelContext
    ) async -> (title: String?, description: String?, bodyText: String?) {
        guard let metadata = await metadataFetcher.fetch(urlString: urlString) else {
            // Clear loading flag even on failure
            let desc = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            if let fetchedItem = try? context.fetch(desc).first {
                fetchedItem.isFetchingMetadata = false
                try? context.save()
            }
            return (nil, nil, nil)
        }

        // The URL had no `.pdf` extension but served a PDF anyway — a very
        // common shape for publisher and university links.
        if metadata.isPDF {
            if let result = await enrichPDFItem(itemID: itemID, urlString: urlString, context: context) {
                return result
            }
            let desc = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            if let item = try? context.fetch(desc).first, let title = metadata.title, !title.isEmpty {
                item.title = title
            }
            finishFetching(itemID: itemID, context: context)
            return (metadata.title, nil, nil)
        }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let fetchedItem = try? context.fetch(descriptor).first else {
            return (metadata.title, metadata.description, metadata.bodyText)
        }

        if let authors = metadata.authors, !authors.isEmpty {
            fetchedItem.authors = authors
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
            fetchedItem.thumbnailURL = imageURLString
            if let imageData = await imageDownloader.downloadAndCompress(urlString: imageURLString) {
                fetchedItem.thumbnail = imageData
            }
        }

        fetchedItem.isFetchingMetadata = false
        fetchedItem.updatedAt = .now
        try? context.save()

        return (metadata.title, metadata.description, metadata.bodyText)
    }

    /// Full enrichment pass for a newsletter issue promoted into the
    /// library: fetch real page metadata, then generate an overview with
    /// the configured LLM (Apple Intelligence by default). If no LLM is
    /// available, the page's own metadata description remains as content.
    func enrichPromotedIssue(itemID: UUID, urlString: String, context: ModelContext) async {
        let (title, description, bodyText) = await enrichURLItem(
            itemID: itemID,
            urlString: urlString,
            context: context
        )

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        let itemTitle = (try? context.fetch(descriptor).first)?.title ?? title ?? ""

        await generateOverview(
            itemID: itemID,
            context: context,
            title: itemTitle,
            description: description,
            bodyText: bodyText
        )
    }

    /// Generates a multi-paragraph overview/summary for an article using the LLM.
    /// Stores the result in `item.overview`; `item.content` stays as it was.
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

        item.recordOverview(overview)
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
              item.summary == nil,
              let sourceText = [item.overview, item.content].compactMap({ $0 }).first(where: { !$0.isEmpty })
        else { return }

        let firstSentence = sourceText
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !firstSentence.isEmpty {
            item.summary = String(firstSentence.prefix(120))
            try? context.save()
        }
    }

    /// Mark generated summaries with provenance without creating another approval queue.
    func markSummaryReviewIfNeeded(
        itemID: UUID,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first,
              item.summary != nil else { return }
        item.isSummaryGeneratedByAI = true
        item.isSummaryReviewPending = false
        item.isOverviewReviewPending = false
        try? context.save()
    }
}
