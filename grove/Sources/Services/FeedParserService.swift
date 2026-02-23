import Foundation

struct FeedArticle {
    let title: String
    let url: String
    let description: String?
    let publishedAt: Date?
    let author: String?
    let imageURL: String?
}

final class FeedParserService: NSObject, XMLParserDelegate {

    static func parse(data: Data) -> [FeedArticle] {
        let parser = FeedParserService()
        return parser.parseData(data)
    }

    // MARK: - State

    private var articles: [FeedArticle] = []
    private var currentElement = ""
    private var currentText = ""

    // Current article fields
    private var articleTitle = ""
    private var articleURL = ""
    private var articleDescription = ""
    private var articlePubDate = ""
    private var articleAuthor = ""
    private var articleImageURL = ""

    // Feed type detection
    private var isInItem = false   // RSS <item> or Atom <entry>
    private var isAtomFeed = false

    // MARK: - Parsing

    private func parseData(_ data: Data) -> [FeedArticle] {
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.shouldProcessNamespaces = false
        xmlParser.shouldReportNamespacePrefixes = false
        xmlParser.parse()
        return articles
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName.lowercased()
        currentText = ""

        switch currentElement {
        case "item":
            isInItem = true
            resetArticleFields()
        case "entry":
            isInItem = true
            isAtomFeed = true
            resetArticleFields()
        case "link":
            if isInItem && isAtomFeed {
                // Atom <link href="..." />
                if let href = attributeDict["href"] {
                    let rel = attributeDict["rel"] ?? "alternate"
                    if rel == "alternate" || articleURL.isEmpty {
                        articleURL = href
                    }
                }
            }
        case "enclosure", "media:content":
            if isInItem, let url = attributeDict["url"] {
                let type = attributeDict["type"] ?? ""
                if type.hasPrefix("image/") || articleImageURL.isEmpty {
                    articleImageURL = url
                }
            }
        case "media:thumbnail":
            if isInItem, let url = attributeDict["url"], articleImageURL.isEmpty {
                articleImageURL = url
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            currentText += text
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let element = elementName.lowercased()

        if isInItem {
            switch element {
            case "title":
                articleTitle = trimmed
            case "link":
                if !isAtomFeed && !trimmed.isEmpty {
                    articleURL = trimmed
                }
            case "description", "summary", "content":
                if articleDescription.isEmpty || element == "content" {
                    articleDescription = Self.stripHTML(trimmed)
                }
            case "pubdate", "published", "updated", "dc:date":
                if articlePubDate.isEmpty {
                    articlePubDate = trimmed
                }
            case "author", "dc:creator":
                if articleAuthor.isEmpty {
                    articleAuthor = trimmed
                }
            case "item", "entry":
                if !articleTitle.isEmpty && !articleURL.isEmpty {
                    let article = FeedArticle(
                        title: articleTitle,
                        url: articleURL,
                        description: articleDescription.isEmpty ? nil : String(articleDescription.prefix(500)),
                        publishedAt: Self.parseDate(articlePubDate),
                        author: articleAuthor.isEmpty ? nil : articleAuthor,
                        imageURL: articleImageURL.isEmpty ? nil : articleImageURL
                    )
                    articles.append(article)
                }
                isInItem = false
            default:
                break
            }
        }

        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Silently fail — return whatever was parsed so far
    }

    // MARK: - Helpers

    private func resetArticleFields() {
        articleTitle = ""
        articleURL = ""
        articleDescription = ""
        articlePubDate = ""
        articleAuthor = ""
        articleImageURL = ""
    }

    private static func stripHTML(_ string: String) -> String {
        let stripped = string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",     // RFC 822
            "EEE, dd MMM yyyy HH:mm:ss zzz",   // RFC 822 variant
            "yyyy-MM-dd'T'HH:mm:ssZ",           // ISO 8601
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",       // ISO 8601 with ms
            "yyyy-MM-dd'T'HH:mm:ssxxxxx",       // ISO 8601 with colon offset
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }
    }()

    private static func parseDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        // Try ISO8601DateFormatter as last resort
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: string)
    }
}
