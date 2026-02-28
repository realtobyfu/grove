import Foundation

/// Resolve a source URL string into a loadable URL.
/// Accepts already-valid URLs, trims surrounding whitespace, percent-encodes recoverable input,
/// and falls back to `https://` when the source omits a scheme.
func resolvedSourceURL(from rawSourceURL: String?) -> URL? {
    guard let rawSourceURL else { return nil }

    let trimmed = rawSourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let candidates = [
        trimmed,
        trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
        "https://\(trimmed)",
        "https://\(trimmed)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    ]

    for candidate in candidates {
        guard let candidate else { continue }
        guard let url = URL(string: candidate), url.scheme?.isEmpty == false else { continue }
        return url
    }

    return nil
}

/// Extract the display domain from a URL string, stripping "www." prefix.
/// Shared across InboxCard, ItemCardView, and any other view that shows source domains.
func domainFrom(_ urlString: String) -> String {
    guard let url = resolvedSourceURL(from: urlString),
          let host = url.host else {
        return urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return host.replacingOccurrences(of: "www.", with: "")
}
