import Foundation

/// Paper metadata as returned by the arXiv Atom API.
struct ArxivMetadata: Sendable {
    var title: String
    var authors: [String]
    var summary: String
    var published: Date?
}

/// Fetches canonical paper metadata from the arXiv export API.
///
/// arXiv abstract pages are scrape-hostile and their OpenGraph tags are thin,
/// but the public Atom API gives the real title, the full author list, and the
/// abstract for free. Parsed with Foundation's `XMLParser` — no dependencies.
enum ArxivMetadataService {

    private static let timeout: TimeInterval = 10

    /// Returns nil on any network, HTTP, or parse failure — enrichment falls
    /// back to the generic HTML path.
    static func fetch(arxivID: String) async -> ArxivMetadata? {
        guard var components = URLComponents(string: "https://export.arxiv.org/api/query") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "id_list", value: arxivID),
            URLQueryItem(name: "max_results", value: "1"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }
            return parse(atom: data)
        } catch {
            return nil
        }
    }

    // MARK: - Atom Parsing

    static func parse(atom data: Data) -> ArxivMetadata? {
        let delegate = AtomEntryParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse(), delegate.didFindEntry else { return nil }

        let title = collapseWhitespace(delegate.title)
        let summary = collapseWhitespace(delegate.summary)
        guard !title.isEmpty else { return nil }

        return ArxivMetadata(
            title: title,
            authors: delegate.authors,
            summary: summary,
            published: delegate.published.flatMap { ISO8601DateFormatter().date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    private static func collapseWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Accumulates the first `<entry>` of an arXiv Atom feed.
///
/// `XMLParser` hands text back in arbitrary chunks, so every field is appended
/// to and only normalized once parsing finishes.
private final class AtomEntryParser: NSObject, XMLParserDelegate {
    private(set) var didFindEntry = false
    private(set) var title = ""
    private(set) var summary = ""
    private(set) var authors: [String] = []
    private(set) var published: String?

    private var inEntry = false
    private var finishedEntry = false
    private var inAuthor = false
    private var currentAuthorName = ""
    private var currentPublished = ""
    private var currentElement: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        currentElement = elementName
        switch elementName {
        case "entry" where !finishedEntry:
            inEntry = true
            didFindEntry = true
        case "author" where inEntry:
            inAuthor = true
            currentAuthorName = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry, let currentElement else { return }
        switch currentElement {
        case "title":
            title += string
        case "summary":
            summary += string
        case "name" where inAuthor:
            currentAuthorName += string
        case "published":
            currentPublished += string
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "entry" where inEntry:
            inEntry = false
            finishedEntry = true
            published = currentPublished.isEmpty ? nil : currentPublished
        case "author" where inAuthor:
            inAuthor = false
            let name = currentAuthorName
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !name.isEmpty { authors.append(name) }
        default:
            break
        }
        currentElement = nil
    }
}
