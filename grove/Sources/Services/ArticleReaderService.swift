import Foundation

// MARK: - Article Reader Service Protocol
// Stub for testability. Future iterations may add server-side
// readability extraction (Readability.js, Mercury Parser, etc.).

protocol ArticleReaderServiceProtocol {
    /// Returns a plain-text readable version of the article at the given URL.
    /// Returns nil if extraction fails or is not supported.
    func extractReadableText(from url: URL) async -> String?
}

// MARK: - Article Reader Service

final class ArticleReaderService: ArticleReaderServiceProtocol, Sendable {
    static let shared = ArticleReaderService()

    private init() {}

    /// Currently a no-op — extraction is handled by the in-app WKWebView.
    func extractReadableText(from url: URL) async -> String? {
        return nil
    }
}
