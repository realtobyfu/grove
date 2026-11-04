import Foundation
import SQLiteData

/// Handles metadata fetching, thumbnail download, and LLM overview generation for Items.
/// Extracted from CaptureService to isolate enrichment responsibilities.
///
/// Everything here waits on the network, and a transaction can't span that wait.
/// So it works from an item ID and re-reads the row when it writes: the item may
/// have been edited or deleted in the meantime.
@MainActor
@Observable
final class ItemMetadataEnricher {
    private let database: any DatabaseWriter
    private let metadataFetcher: URLMetadataFetcherProtocol
    private let imageDownloader: ImageDownloadServiceProtocol

    init(
        database: any DatabaseWriter = AppDatabase.current,
        metadataFetcher: URLMetadataFetcherProtocol = URLMetadataFetcher.shared,
        imageDownloader: ImageDownloadServiceProtocol = ImageDownloadService.shared
    ) {
        self.database = database
        self.metadataFetcher = metadataFetcher
        self.imageDownloader = imageDownloader
    }

    private func fetchItem(_ itemID: UUID) -> Item? {
        database.attemptRead { try Item.find(itemID).fetchOne($0) } ?? nil
    }

    /// Changes the item and stores `thumbnail` in one transaction. Returns false
    /// when the item is gone, which is not an error: the user deleted it while
    /// we were waiting on the network.
    @discardableResult
    private func updateItem(
        _ itemID: UUID,
        thumbnail: Data? = nil,
        _ changes: (inout Item) -> Void
    ) -> Bool {
        database.attempt { db in
            guard try Item.modify(itemID, in: db, changes) != nil else { return false }
            // After the check above: a thumbnail's foreign key would fail the
            // transaction if the item had gone.
            if let thumbnail {
                try Item.setThumbnail(thumbnail, forItem: itemID, in: db)
            }
            return true
        } ?? false
    }

    /// Fetches URL metadata and updates the item.
    /// Returns the fetched metadata title and description for downstream use.
    ///
    /// Sources that publish structured metadata get a dedicated path — arXiv's
    /// Atom API, oEmbed for video, the PDF document itself — because scraping
    /// their HTML yields either nothing or the wrong thing. Every specialized
    /// path falls back to the generic scrape if it comes up empty.
    func enrichURLItem(
        itemID: UUID,
        urlString: String
    ) async -> (title: String?, description: String?, bodyText: String?) {
        let routing = routingInfo(itemID: itemID)

        if let arxivID = routing.arxivID,
           let result = await enrichArxivItem(itemID: itemID, arxivID: arxivID) {
            return result
        } else if routing.isVideo,
                  let source = routing.videoSource,
                  let videoID = routing.videoID,
                  let result = await enrichVideoItem(
                      itemID: itemID,
                      source: source,
                      videoID: videoID,
                      urlString: urlString
                  ) {
            return result
        } else if routing.isPDF,
                  let result = await enrichPDFItem(itemID: itemID, urlString: urlString) {
            return result
        }

        return await enrichGenericURLItem(itemID: itemID, urlString: urlString)
    }

    private struct EnrichmentRouting {
        var arxivID: String?
        var videoSource: String?
        var videoID: String?
        var isVideo = false
        var isPDF = false
    }

    private func routingInfo(itemID: UUID) -> EnrichmentRouting {
        guard let item = fetchItem(itemID) else { return EnrichmentRouting() }
        return EnrichmentRouting(
            arxivID: item.metadata["arxivID"],
            videoSource: item.metadata["videoSource"],
            videoID: item.metadata["videoID"],
            isVideo: item.type == .video,
            isPDF: item.metadata["format"] == "pdf"
        )
    }

    /// Clears the loading flag so a failed fetch doesn't leave a permanent spinner.
    private func finishFetching(itemID: UUID, title: String? = nil) {
        updateItem(itemID) { item in
            if let title, !title.isEmpty {
                item.title = title
            }
            item.metadata["fetchingMetadata"] = nil
            item.updatedAt = .now
        }
    }

    // MARK: - arXiv

    private func enrichArxivItem(
        itemID: UUID,
        arxivID: String
    ) async -> (title: String?, description: String?, bodyText: String?)? {
        guard let paper = await ArxivMetadataService.fetch(arxivID: arxivID) else { return nil }

        let saved = updateItem(itemID) { item in
            item.title = paper.title
            if !paper.summary.isEmpty {
                item.content = paper.summary
            }
            if !paper.authors.isEmpty {
                item.metadata["authors"] = paper.authors.joined(separator: ", ")
            }
            item.metadata["fetchingMetadata"] = nil
            item.updatedAt = .now
        }
        guard saved else {
            return (paper.title, paper.summary, paper.summary)
        }

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
        urlString: String
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

        updateItem(itemID, thumbnail: thumbnailData) { item in
            if let title, !title.isEmpty {
                item.title = title
            }
            if let description, !description.isEmpty {
                item.content = description
            }
            if let author = oembed?.authorName, !author.isEmpty {
                item.metadata["authors"] = author
            }
            if let thumbnailURL {
                item.metadata["thumbnailURL"] = thumbnailURL
            }
            if let duration = oembed?.duration ?? scraped?.durationSeconds {
                // Same format the local-video importer writes.
                item.metadata["videoDuration"] = String(format: "%.1f", Double(duration))
            }
            item.metadata["fetchingMetadata"] = nil
            item.updatedAt = .now
        }

        return (title, description, scraped?.bodyText)
    }

    // MARK: - PDF

    private func enrichPDFItem(
        itemID: UUID,
        urlString: String
    ) async -> (title: String?, description: String?, bodyText: String?)? {
        guard let url = URL(string: urlString) else { return nil }

        // Record the format even if the download later fails: the URL is a PDF
        // either way, and the reader routes on this key.
        markPDFFormat(itemID: itemID)

        guard let extracted = await PDFMetadataService.downloadAndExtract(
            url: url,
            itemID: itemID
        ) else { return nil }

        updateItem(itemID, thumbnail: extracted.thumbnailData) { item in
            if let title = extracted.title, !title.isEmpty {
                item.title = title
            }
            if let author = extracted.author, !author.isEmpty {
                item.metadata["authors"] = author
            }
            item.metadata["pdfCached"] = "true"
            item.metadata["fetchingMetadata"] = nil
            item.updatedAt = .now
        }

        return (extracted.title, nil, nil)
    }

    private func markPDFFormat(itemID: UUID) {
        updateItem(itemID) { $0.metadata["format"] = "pdf" }
    }

    // MARK: - Generic

    private func enrichGenericURLItem(
        itemID: UUID,
        urlString: String
    ) async -> (title: String?, description: String?, bodyText: String?) {
        guard let metadata = await metadataFetcher.fetch(urlString: urlString) else {
            // Clear loading flag even on failure
            updateItem(itemID) { $0.metadata["fetchingMetadata"] = nil }
            return (nil, nil, nil)
        }

        // The URL had no `.pdf` extension but served a PDF anyway — a very
        // common shape for publisher and university links.
        if metadata.isPDF {
            if let result = await enrichPDFItem(itemID: itemID, urlString: urlString) {
                return result
            }
            finishFetching(itemID: itemID, title: metadata.title)
            return (metadata.title, nil, nil)
        }

        // Prefer LP image data (works on bot-protected sites), fall back to URL download
        let compressedImage = metadata.imageData.flatMap { imageDownloader.compressImageData($0) }
        let imageURLString = compressedImage == nil ? metadata.imageURL : nil

        // The text goes in now so the title doesn't wait on the image download.
        // An item deleted during the fetch also skips that download here.
        let saved = updateItem(itemID, thumbnail: compressedImage) { item in
            if let authors = metadata.authors, !authors.isEmpty {
                item.metadata["authors"] = authors
            }
            if let title = metadata.title {
                item.title = title
            }
            if let description = metadata.description {
                item.content = description
            }
            if let imageURLString {
                item.metadata["thumbnailURL"] = imageURLString
            }
        }
        guard saved else {
            return (metadata.title, metadata.description, metadata.bodyText)
        }

        var downloadedImage: Data?
        if let imageURLString {
            downloadedImage = await imageDownloader.downloadAndCompress(urlString: imageURLString)
        }

        updateItem(itemID, thumbnail: downloadedImage) { item in
            item.metadata["fetchingMetadata"] = nil
            item.updatedAt = .now
        }

        return (metadata.title, metadata.description, metadata.bodyText)
    }

    /// Full enrichment pass for a newsletter issue promoted into the
    /// library: fetch real page metadata, then generate an overview with
    /// the configured LLM (Apple Intelligence by default). If no LLM is
    /// available, the page's own metadata description remains as content.
    func enrichPromotedIssue(itemID: UUID, urlString: String) async {
        let (title, description, bodyText) = await enrichURLItem(
            itemID: itemID,
            urlString: urlString
        )

        let itemTitle = fetchItem(itemID)?.title ?? title ?? ""

        await generateOverview(
            itemID: itemID,
            title: itemTitle,
            description: description,
            bodyText: bodyText
        )
    }

    /// Generates a multi-paragraph overview/summary for an article using the LLM.
    /// Stores the result in item.content, replacing the short OG description.
    func generateOverview(
        itemID: UUID,
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

        updateItem(itemID) { item in
            if let original = item.content, !original.isEmpty {
                item.metadata["originalDescription"] = original
            }
            item.content = overview
            item.metadata["hasLLMOverview"] = "true"
            item.metadata["overviewGeneratedByAI"] = "true"
            item.updatedAt = .now
        }
    }

    /// After metadata enrichment, extract a summary fallback from the overview if needed.
    func extractSummaryFallback(itemID: UUID) {
        database.attempt { db in
            guard let item = try Item.find(itemID).fetchOne(db),
                  item.metadata["summary"] == nil,
                  let overviewContent = item.content, !overviewContent.isEmpty else { return }

            let firstSentence = overviewContent
                .components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !firstSentence.isEmpty {
                try Item.modify(itemID, in: db) {
                    $0.metadata["summary"] = String(firstSentence.prefix(120))
                }
            }
        }
    }

    /// Mark generated summaries with provenance without creating another approval queue.
    func markSummaryReviewIfNeeded(itemID: UUID) {
        database.attempt { db in
            guard let item = try Item.find(itemID).fetchOne(db),
                  item.metadata["summary"] != nil else { return }
            try Item.modify(itemID, in: db) {
                $0.metadata["summaryGeneratedByAI"] = "true"
                $0.metadata["summaryReviewPending"] = nil
                $0.metadata["overviewReviewPending"] = nil
            }
        }
    }
}
