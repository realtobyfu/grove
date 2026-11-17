import Foundation
import SwiftData

/// Handles metadata fetching, thumbnail download, and LLM overview generation for Items.
/// Extracted from CaptureService to isolate enrichment responsibilities.
/// How an enrichment pass treats text already on the item.
enum MetadataWriteMode: Sendable {
    /// First capture: the title is a placeholder and there is no content yet,
    /// so fetched values replace whatever is there.
    case initialCapture
    /// A later refresh: fetched title and content only fill a placeholder
    /// title or an empty content, because either may be the user's by now.
    /// Thumbnail, authors and the other fetched metadata still update.
    case refresh
}

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
        context: ModelContext,
        overwrite mode: MetadataWriteMode = .initialCapture
    ) async -> (title: String?, description: String?, bodyText: String?) {
        let routing = routingInfo(itemID: itemID, context: context)

        if let arxivID = routing.arxivID,
           let result = await enrichArxivItem(itemID: itemID, arxivID: arxivID, context: context, mode: mode) {
            return result
        } else if routing.isVideo,
                  let source = routing.videoSource,
                  let videoID = routing.videoID,
                  let result = await enrichVideoItem(
                      itemID: itemID,
                      source: source,
                      videoID: videoID,
                      urlString: urlString,
                      context: context,
                      mode: mode
                  ) {
            return result
        } else if routing.isPDF,
                  let result = await enrichPDFItem(itemID: itemID, urlString: urlString, context: context, mode: mode) {
            return result
        }

        return await enrichGenericURLItem(itemID: itemID, urlString: urlString, context: context, mode: mode)
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

    // MARK: - Writing fetched text

    /// Writes a fetched title. In refresh mode only a placeholder title is
    /// replaced, so a title the user typed survives.
    private func writeTitle(_ title: String?, to item: Item, mode: MetadataWriteMode, urlString: String) {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if mode == .refresh,
           !Self.isPlaceholderTitle(item.title, urlString: urlString, sourceURL: item.sourceURL) {
            return
        }
        item.title = title
    }

    /// Writes fetched content. In refresh mode only empty content is filled.
    private func writeContent(_ content: String?, to item: Item, mode: MetadataWriteMode) {
        guard let content else { return }
        if mode == .refresh,
           !(item.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        item.content = content
    }

    /// The titles capture writes before metadata arrives: nothing, the URL
    /// itself (in-app capture and the share extension), or its host.
    nonisolated static func isPlaceholderTitle(_ title: String, urlString: String, sourceURL: String?) -> Bool {
        let current = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty { return true }
        let lowered = current.lowercased()
        for candidate in [urlString, sourceURL].compactMap({ $0 }) {
            if current == candidate.trimmingCharacters(in: .whitespacesAndNewlines) { return true }
            guard let host = URL(string: candidate)?.host?.lowercased() else { continue }
            let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let bareTitle = lowered.hasPrefix("www.") ? String(lowered.dropFirst(4)) : lowered
            if bareTitle == bareHost { return true }
        }
        return false
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
        context: ModelContext,
        mode: MetadataWriteMode
    ) async -> (title: String?, description: String?, bodyText: String?)? {
        guard let paper = await ArxivMetadataService.fetch(arxivID: arxivID) else { return nil }

        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else {
            return (paper.title, paper.summary, paper.summary)
        }

        writeTitle(paper.title, to: item, mode: mode, urlString: item.sourceURL ?? "")
        if !paper.summary.isEmpty {
            writeContent(paper.summary, to: item, mode: mode)
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
        context: ModelContext,
        mode: MetadataWriteMode
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

        writeTitle(title, to: item, mode: mode, urlString: urlString)
        if let description, !description.isEmpty {
            writeContent(description, to: item, mode: mode)
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
        context: ModelContext,
        mode: MetadataWriteMode
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

        writeTitle(extracted.title, to: item, mode: mode, urlString: urlString)
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
        context: ModelContext,
        mode: MetadataWriteMode
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
            if let result = await enrichPDFItem(itemID: itemID, urlString: urlString, context: context, mode: mode) {
                return result
            }
            let desc = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
            if let item = try? context.fetch(desc).first {
                writeTitle(metadata.title, to: item, mode: mode, urlString: urlString)
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
        writeTitle(metadata.title, to: fetchedItem, mode: mode, urlString: urlString)
        writeContent(metadata.description, to: fetchedItem, mode: mode)

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
        // An overview that may hold the user's words is never regenerated
        // over; checked before spending a request and again before writing.
        guard overviewMayBeReplaced(itemID: itemID, context: context) else { return }
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
        guard let item = try? context.fetch(descriptor).first,
              overviewMayBeReplaced(itemID: itemID, context: context) else { return }

        item.recordOverview(overview)
        item.updatedAt = .now
        try? context.save()
    }

    /// Brings an old-shape item up to date first, since migration decides
    /// where its text lives, then asks whether a new overview may go in.
    func overviewMayBeReplaced(itemID: UUID, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? context.fetch(descriptor).first else { return false }
        if item.migrateLegacyOverviewIfNeeded() {
            try? context.save()
        }
        return item.canReplaceOverview
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
