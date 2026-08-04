import Foundation

/// The subset of an oEmbed response Grove stores on an Item.
struct OEmbedMetadata: Sendable {
    var title: String?
    var authorName: String?
    var thumbnailURL: String?
    /// Runtime in seconds. Vimeo reports it; YouTube's oEmbed does not.
    var duration: Int?
}

/// Fetches video metadata from the provider's public oEmbed endpoint.
///
/// YouTube and Vimeo watch pages are JavaScript shells whose OpenGraph tags are
/// unreliable behind consent walls, but both expose an unauthenticated oEmbed
/// endpoint that returns the real title, channel, and thumbnail.
enum OEmbedService {

    private static let timeout: TimeInterval = 10

    /// `source` matches the `videoSource` metadata key ("youtube" | "vimeo").
    /// Returns nil on any network, HTTP, or decode failure.
    static func fetch(source: String, videoID: String, originalURL: String) async -> OEmbedMetadata? {
        guard let endpoint = endpointURL(source: source, originalURL: originalURL) else { return nil }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(OEmbedResponse.self, from: data)
            return OEmbedMetadata(
                title: decoded.title,
                authorName: decoded.author_name,
                thumbnailURL: decoded.thumbnail_url,
                duration: decoded.duration
            )
        } catch {
            return nil
        }
    }

    private static func endpointURL(source: String, originalURL: String) -> URL? {
        let base: String
        switch source.lowercased() {
        case "youtube":
            base = "https://www.youtube.com/oembed"
        case "vimeo":
            base = "https://vimeo.com/api/oembed.json"
        default:
            return nil
        }

        guard var components = URLComponents(string: base) else { return nil }
        var items = [URLQueryItem(name: "url", value: originalURL)]
        if source.lowercased() == "youtube" {
            items.append(URLQueryItem(name: "format", value: "json"))
        }
        components.queryItems = items
        return components.url
    }

    private struct OEmbedResponse: Decodable {
        // swiftlint:disable identifier_name — oEmbed wire format is snake_case.
        var title: String?
        var author_name: String?
        var thumbnail_url: String?
        var duration: Int?
        // swiftlint:enable identifier_name
    }
}
