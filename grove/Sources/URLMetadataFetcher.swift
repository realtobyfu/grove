import Foundation

struct URLMetadata: Sendable {
    var title: String?
    var description: String?
    var imageURL: String?
}

/// Fetches OpenGraph and HTML meta tags from a URL to populate Item metadata.
final class URLMetadataFetcher: Sendable {

    static let shared = URLMetadataFetcher()

    private init() {}

    /// Fetch metadata for the given URL string. Returns nil on failure.
    func fetch(urlString: String) async -> URLMetadata? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // Some sites block non-browser user agents
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            guard let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                return nil
            }

            return parse(html: html)
        } catch {
            return nil
        }
    }

    // MARK: - HTML Parsing

    private func parse(html: String) -> URLMetadata {
        var metadata = URLMetadata()

        // Try OpenGraph tags first
        metadata.title = extractMetaContent(html: html, property: "og:title")
        metadata.description = extractMetaContent(html: html, property: "og:description")
        metadata.imageURL = extractMetaContent(html: html, property: "og:image")

        // Fallback: <title> tag
        if metadata.title == nil {
            metadata.title = extractTitleTag(html: html)
        }

        // Fallback: meta description
        if metadata.description == nil {
            metadata.description = extractMetaContent(html: html, name: "description")
        }

        // Fallback: twitter card tags
        if metadata.title == nil {
            metadata.title = extractMetaContent(html: html, name: "twitter:title")
        }
        if metadata.description == nil {
            metadata.description = extractMetaContent(html: html, name: "twitter:description")
        }
        if metadata.imageURL == nil {
            metadata.imageURL = extractMetaContent(html: html, name: "twitter:image")
        }

        return metadata
    }

    /// Extract content from `<meta property="..." content="...">` (OpenGraph style)
    private func extractMetaContent(html: String, property: String) -> String? {
        // Matches both property="og:title" content="..." and content="..." property="og:title"
        let patterns = [
            "<meta[^>]+property\\s*=\\s*\"?\(NSRegularExpression.escapedPattern(for: property))\"?[^>]+content\\s*=\\s*\"([^\"]*)\"",
            "<meta[^>]+content\\s*=\\s*\"([^\"]*)\"[^>]+property\\s*=\\s*\"?\(NSRegularExpression.escapedPattern(for: property))\"?"
        ]
        for pattern in patterns {
            if let value = firstMatch(html: html, pattern: pattern) {
                let cleaned = value.decodingHTMLEntities()
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    /// Extract content from `<meta name="..." content="...">` (standard HTML meta)
    private func extractMetaContent(html: String, name: String) -> String? {
        let patterns = [
            "<meta[^>]+name\\s*=\\s*\"?\(NSRegularExpression.escapedPattern(for: name))\"?[^>]+content\\s*=\\s*\"([^\"]*)\"",
            "<meta[^>]+content\\s*=\\s*\"([^\"]*)\"[^>]+name\\s*=\\s*\"?\(NSRegularExpression.escapedPattern(for: name))\"?"
        ]
        for pattern in patterns {
            if let value = firstMatch(html: html, pattern: pattern) {
                let cleaned = value.decodingHTMLEntities()
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    /// Extract the content of the `<title>` tag
    private func extractTitleTag(html: String) -> String? {
        if let value = firstMatch(html: html, pattern: "<title[^>]*>([^<]+)</title>") {
            let cleaned = value.decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    /// Return the first capture group match for the given regex pattern
    private func firstMatch(html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[captureRange])
    }
}

// MARK: - HTML Entity Decoding

private extension String {
    func decodingHTMLEntities() -> String {
        var result = self
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&#x27;", "'"),
            ("&nbsp;", " "),
            ("&#x2F;", "/"),
            ("&#47;", "/"),
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Decode numeric entities like &#123;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                if let codeRange = Range(match.range(at: 1), in: result),
                   let code = UInt32(result[codeRange]),
                   let scalar = Unicode.Scalar(code) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        return result
    }
}
