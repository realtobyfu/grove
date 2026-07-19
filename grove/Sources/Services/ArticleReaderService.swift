import Foundation
import WebKit

// MARK: - Readable Article

/// The result of a Readability.js extraction, cacheable to disk so the
/// reader view can render offline without re-loading the live page.
struct ReadableArticle: Codable, Equatable, Sendable {
    var title: String
    var byline: String?
    /// Cleaned article body as HTML (Readability's `content`).
    var contentHTML: String
    /// Plain-text version of the article body (Readability's `textContent`).
    var textContent: String
    /// Character length of the extracted text (Readability's `length`).
    var length: Int
    var excerpt: String?
    /// The URL the article was extracted from, for resolving relative images.
    var sourceURLString: String?
    var extractedAt: Date
    /// Word count computed once at extraction time.
    var wordCount: Int

    /// Estimated reading time at ~230 words per minute, minimum 1 minute.
    var readMinutes: Int {
        max(1, Int((Double(wordCount) / 230.0).rounded(.up)))
    }
}

// MARK: - Article Reader Service Protocol

@MainActor
protocol ArticleReaderServiceProtocol {
    /// Runs Readability.js inside a WKWebView whose page has finished loading.
    /// Returns nil when the page is not extractable (parse failure, paywall shell,
    /// near-empty result).
    func extractArticle(from webView: WKWebView, sourceURL: URL?) async -> ReadableArticle?

    nonisolated func cachedArticle(for itemID: UUID) -> ReadableArticle?
    nonisolated func hasCachedArticle(for itemID: UUID) -> Bool
    nonisolated func saveArticle(_ article: ReadableArticle, for itemID: UUID)
    nonisolated func removeCachedArticle(for itemID: UUID)
}

// MARK: - Article Reader Service

/// Extracts a clean, readable version of a web article by injecting the
/// bundled Mozilla Readability.js into an already-loaded WKWebView, and
/// caches results on disk (Application Support/GroveReaderCache/<itemUUID>.json).
final class ArticleReaderService: ArticleReaderServiceProtocol, Sendable {
    static let shared = ArticleReaderService()

    /// Extractions shorter than this (characters) are treated as failures —
    /// typically paywall shells or navigation-only pages.
    private static let minimumExtractedLength = 500

    private init() {}

    // MARK: - Extraction

    /// Fields marshalled back from Readability.parse() via JSON.stringify.
    private struct ReadabilityPayload: Decodable {
        var title: String?
        var byline: String?
        var content: String?
        var textContent: String?
        var length: Int?
        var excerpt: String?
    }

    /// Bundled Readability.js source, loaded once.
    private static let readabilitySource: String? = {
        guard let url = Bundle.main.url(forResource: "Readability", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return source
    }()

    @MainActor
    func extractArticle(from webView: WKWebView, sourceURL: URL?) async -> ReadableArticle? {
        guard let readability = Self.readabilitySource else { return nil }

        // Wrap the library in an IIFE so it never pollutes the page's global
        // scope, clone the document so extraction cannot mutate the live page,
        // and marshal the result back as a JSON string.
        let script = """
        (function() {
            try {
                \(readability)
                var article = new Readability(document.cloneNode(true)).parse();
                if (!article || !article.content || !article.textContent) { return null; }
                return JSON.stringify({
                    title: article.title,
                    byline: article.byline,
                    content: article.content,
                    textContent: article.textContent,
                    length: article.length,
                    excerpt: article.excerpt
                });
            } catch (e) {
                return null;
            }
        })();
        """

        let json: String? = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result as? String)
            }
        }

        guard let json, let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ReadabilityPayload.self, from: data),
              let contentHTML = payload.content,
              let textContent = payload.textContent else {
            return nil
        }

        let trimmed = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumExtractedLength else { return nil }

        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count

        return ReadableArticle(
            title: payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            byline: payload.byline?.trimmingCharacters(in: .whitespacesAndNewlines),
            contentHTML: contentHTML,
            textContent: textContent,
            length: payload.length ?? trimmed.count,
            excerpt: payload.excerpt,
            sourceURLString: sourceURL?.absoluteString,
            extractedAt: .now,
            wordCount: wordCount
        )
    }

    // MARK: - Disk Cache

    private nonisolated var cacheDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("GroveReaderCache", isDirectory: true)
    }

    private nonisolated func cacheURL(for itemID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(itemID.uuidString).json")
    }

    nonisolated func hasCachedArticle(for itemID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: cacheURL(for: itemID).path)
    }

    nonisolated func cachedArticle(for itemID: UUID) -> ReadableArticle? {
        guard let data = try? Data(contentsOf: cacheURL(for: itemID)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ReadableArticle.self, from: data)
    }

    nonisolated func saveArticle(_ article: ReadableArticle, for itemID: UUID) {
        do {
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(article)
            try data.write(to: cacheURL(for: itemID), options: .atomic)
        } catch {
            // Cache write failure is non-fatal; extraction still lives in memory.
        }
    }

    nonisolated func removeCachedArticle(for itemID: UUID) {
        try? FileManager.default.removeItem(at: cacheURL(for: itemID))
    }
}
