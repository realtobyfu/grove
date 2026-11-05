import Foundation
import SwiftData
import SwiftUI

@MainActor
protocol CaptureServiceProtocol {
    func captureItem(input: String, board: Board?) -> Item
    func captureItemDetailed(input: String, board: Board?) -> (item: Item, isDuplicate: Bool)
}

@MainActor
@Observable
final class CaptureService: CaptureServiceProtocol {
    private var modelContext: ModelContext
    private let enricher: ItemMetadataEnricher
    private let tagger: ItemAutoTagger

    init(
        modelContext: ModelContext,
        metadataFetcher: URLMetadataFetcherProtocol = URLMetadataFetcher.shared,
        imageDownloader: ImageDownloadServiceProtocol = ImageDownloadService.shared,
        onBoardSuggestion: BoardSuggestionCallback? = nil
    ) {
        self.modelContext = modelContext
        self.enricher = ItemMetadataEnricher(
            metadataFetcher: metadataFetcher,
            imageDownloader: imageDownloader
        )
        self.tagger = ItemAutoTagger(onBoardSuggestion: onBoardSuggestion)
    }

    /// Quick capture: detects URL vs plain text, creates appropriate Item.
    /// Metadata fetching and auto-tagging run asynchronously after creation.
    func captureItem(input: String, board: Board? = nil) -> Item {
        captureItemDetailed(input: input, board: board).item
    }

    /// Like `captureItem`, but reports whether an already-captured item was
    /// returned instead of creating a duplicate (matched by normalized source URL).
    func captureItemDetailed(input: String, board: Board? = nil) -> (item: Item, isDuplicate: Bool) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed),
           let scheme = url.scheme,
           ["http", "https"].contains(scheme.lowercased()),
           url.host != nil {
            if let existing = existingItem(matchingURL: trimmed) {
                // Honor an explicit board target even on a duplicate, so
                // "save to Research" isn't a silent no-op for an existing item.
                if let board, !existing.boards.contains(where: { $0.id == board.id }) {
                    existing.boards.append(board)
                    try? modelContext.save()
                }
                return (existing, true)
            }
            return (captureURLItem(trimmed, board: board), false)
        } else {
            return (captureTextItem(trimmed, board: board), false)
        }
    }

    // MARK: - URL Dedupe

    /// Normalizes a URL for duplicate detection: lowercases scheme/host,
    /// strips the fragment, tracking (`utm_*`) query params, and any trailing slash.
    nonisolated static func normalizedURLString(_ urlString: String) -> String {
        // arXiv serves the same paper under /abs/, /pdf/, /html/, several hosts,
        // and any number of version suffixes. Collapse all of them onto the
        // canonical abstract page so re-capturing from a different surface is
        // recognized as the duplicate it is.
        if let url = URL(string: urlString), let id = arxivID(from: url) {
            return canonicalArxivURLString(id)
        }
        guard var components = URLComponents(string: urlString) else { return urlString }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if let queryItems = components.queryItems {
            let kept = queryItems.filter { !$0.name.lowercased().hasPrefix("utm_") }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        return components.string ?? urlString
    }

    /// Public lookup for surfaces that need to know whether a page is already
    /// in the library *before* acting on it — the reader's capture button
    /// resolves its state from this on every navigation, and must never
    /// re-capture a page it can already see.
    func existingItem(forURL urlString: String) -> Item? {
        existingItem(matchingURL: urlString)
    }

    /// Returns an existing item whose source URL matches the given URL after normalization.
    private func existingItem(matchingURL urlString: String) -> Item? {
        let normalized = Self.normalizedURLString(urlString)
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.sourceURL != nil })
        let candidates = (try? modelContext.fetch(descriptor)) ?? []
        return candidates.first { candidate in
            guard let source = candidate.sourceURL else { return false }
            guard Self.normalizedURLString(source) == normalized else { return false }
            // Only dedupe against items the user can still reach. A dismissed,
            // archived, or expired-suggestion item is invisible in every list,
            // so treating it as a duplicate would silently swallow a deliberate
            // re-capture with no way to surface the item.
            if candidate.status == .dismissed || candidate.status == .archived { return false }
            if candidate.metadata["suggestionDismissed"] == "true" { return false }
            return true
        }
    }

    // MARK: - URL Classification

    /// Applies everything Grove derives from the URL shape alone: the canonical
    /// source URL, the item type, and the metadata keys the enricher routes on.
    ///
    /// In-app capture and the Share Extension drain both run this, so an item
    /// saved from the share sheet is indistinguishable from one captured in the
    /// app — same type, same arXiv/PDF/video routing.
    static func applyURLClassification(item: Item, urlString: String) {
        let url = URL(string: urlString)
        let arxivID = url.flatMap { Self.arxivID(from: $0) }
        // Store the canonical abstract URL so the reader, the enricher, and any
        // later dedupe all agree on which page this item actually is.
        let storedURL = arxivID.map { Self.canonicalArxivURLString($0) } ?? urlString
        item.sourceURL = storedURL

        if let arxivID {
            item.metadata["arxivID"] = arxivID
        } else if let url, url.pathExtension.lowercased() == "pdf" {
            item.metadata["format"] = "pdf"
        }

        let itemType: ItemType
        if Self.isGitHubURL(urlString) {
            itemType = .codebase
        } else if Self.isVideoURL(urlString) {
            itemType = .video
        } else {
            itemType = .article
        }
        item.type = itemType

        if itemType == .video, let url, let video = Self.videoSourceAndID(from: url) {
            item.metadata["videoSource"] = video.source
            item.metadata["videoID"] = video.id
        }
    }

    // MARK: - URL Capture

    private func captureURLItem(_ trimmed: String, board: Board?) -> Item {
        let item = Item(title: trimmed, type: .article)
        prepare(item, for: board)
        Self.applyURLClassification(item: item, urlString: trimmed)

        // The classification may have rewritten the URL (arXiv canonicalization);
        // the placeholder title and the enrichment both follow it.
        let storedURL = item.sourceURL ?? trimmed
        item.title = storedURL
        item.metadata["fetchingMetadata"] = "true"

        modelContext.insert(item)
        try? modelContext.save()

        let itemID = item.id
        let context = self.modelContext
        let enricher = self.enricher
        let tagger = self.tagger

        Task {
            _ = await enricher.enrichURLItem(
                itemID: itemID,
                urlString: storedURL,
                context: context
            )

            // Auto-tag after metadata is available
            await tagger.autoTagItem(itemID: itemID, context: context)

            // Mark summary review if needed
            enricher.markSummaryReviewIfNeeded(itemID: itemID, context: context)
        }

        return item
    }

    // MARK: - Text Capture

    private func captureTextItem(_ trimmed: String, board: Board?) -> Item {
        let title = String(trimmed.prefix(80))
        let item = Item(title: title, type: .note)
        prepare(item, for: board)
        item.content = trimmed
        modelContext.insert(item)
        try? modelContext.save()

        let itemID = item.id
        let context = self.modelContext
        let tagger = self.tagger

        Task {
            await tagger.autoTagItem(itemID: itemID, context: context)
        }

        return item
    }

    /// A destination selected by the user is an approval decision. Captures without
    /// a destination remain in the inbox, including items with passive AI suggestions.
    private func prepare(_ item: Item, for board: Board?) {
        guard let board else {
            item.status = .inbox
            return
        }

        item.status = .active
        item.boards.append(board)
    }

    // MARK: - URL Detection Helpers

    /// Whether the URL should be captured as a video.
    ///
    /// Anything `videoSourceAndID` recognizes is a video by definition — that
    /// covers watch/shorts/live/embed/v, youtu.be, the nocookie/music/m hosts,
    /// and both Vimeo shapes. The substring checks stay as a wider net for the
    /// forms Grove has no oEmbed provider for (Twitch channels, Vimeo channel
    /// and showcase pages), which were classified `.video` before and still are.
    nonisolated static func isVideoURL(_ urlString: String) -> Bool {
        if let url = URL(string: urlString), videoSourceAndID(from: url) != nil {
            return true
        }
        let lower = urlString.lowercased()
        return lower.contains("youtube.com/watch")
            || lower.contains("youtu.be/")
            || lower.contains("vimeo.com/")
            || lower.contains("twitch.tv/")
    }

    private static func isGitHubURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "github.com" || host == "www.github.com"
    }

    // MARK: - arXiv

    private nonisolated static let arxivHosts: Set<String> = [
        "arxiv.org",
        "www.arxiv.org",
        "export.arxiv.org",
        "ar5iv.labs.arxiv.org",
        "ar5iv.org",
    ]

    /// Canonical abstract page for an arXiv identifier.
    nonisolated static func canonicalArxivURLString(_ id: String) -> String {
        "https://arxiv.org/abs/\(id)"
    }

    /// Extracts a version-less arXiv identifier from any of the recognized
    /// arXiv/ar5iv URL shapes (`/abs/`, `/pdf/`, `/pdf/….pdf`, `/html/`).
    /// Returns nil for anything that isn't an arXiv paper URL.
    nonisolated static func arxivID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), arxivHosts.contains(host) else { return nil }

        var segments = url.path.split(separator: "/").map(String.init)
        guard let prefix = segments.first?.lowercased(),
              ["abs", "pdf", "html"].contains(prefix) else { return nil }
        segments.removeFirst()
        guard !segments.isEmpty else { return nil }

        var raw = segments.joined(separator: "/")
        if raw.lowercased().hasSuffix(".pdf") {
            raw = String(raw.dropLast(4))
        }
        // Strip the version suffix (v1, v2, …) so every version of a paper
        // resolves to the same identifier.
        if let versionRange = raw.range(of: "v[0-9]+$", options: .regularExpression) {
            raw = String(raw[raw.startIndex..<versionRange.lowerBound])
        }
        guard isValidArxivID(raw) else { return nil }
        return raw
    }

    private nonisolated static func isValidArxivID(_ id: String) -> Bool {
        // New style: 2401.12345 — old style: cs/0112017, math.GT/0309136
        let patterns = [
            "^[0-9]{4}\\.[0-9]{4,5}$",
            "^[a-zA-Z-]+(\\.[a-zA-Z-]+)?/[0-9]{7}$",
        ]
        return patterns.contains { id.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: - Video Source Detection

    /// Extracts the hosting provider and its video identifier from a URL.
    /// Returns nil for video URLs Grove has no oEmbed provider for (e.g. Twitch).
    nonisolated static func videoSourceAndID(from url: URL) -> (source: String, id: String)? {
        guard var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }

        let segments = url.path.split(separator: "/").map(String.init)

        switch host {
        case "youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com":
            if segments.first?.lowercased() == "watch" {
                guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "v" })?.value,
                      isValidYouTubeID(value) else { return nil }
                return ("youtube", value)
            }
            guard segments.count >= 2,
                  ["shorts", "live", "embed", "v"].contains(segments[0].lowercased()),
                  isValidYouTubeID(segments[1]) else { return nil }
            return ("youtube", segments[1])

        case "youtu.be":
            guard let id = segments.first, isValidYouTubeID(id) else { return nil }
            return ("youtube", id)

        case "vimeo.com":
            guard let id = segments.first, isNumericID(id) else { return nil }
            return ("vimeo", id)

        case "player.vimeo.com":
            guard segments.count >= 2,
                  segments[0].lowercased() == "video",
                  isNumericID(segments[1]) else { return nil }
            return ("vimeo", segments[1])

        default:
            return nil
        }
    }

    private nonisolated static func isValidYouTubeID(_ id: String) -> Bool {
        !id.isEmpty && id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    }

    private nonisolated static func isNumericID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy(\.isNumber)
    }
}
