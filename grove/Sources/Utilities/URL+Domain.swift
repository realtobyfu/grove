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

/// Whether two URLs address the same page, compared on the app's normalized
/// form so a trailing slash, a tracking parameter, or a case difference in the
/// host doesn't read as a different page.
func isSameWebPage(_ lhs: URL?, _ rhs: URL?) -> Bool {
    guard let lhs, let rhs else { return false }
    return CaptureService.normalizedURLString(lhs.absoluteString)
        == CaptureService.normalizedURLString(rhs.absoluteString)
}

// MARK: - Remote Video Embeds

/// Where a video that lives on someone else's site actually plays.
///
/// A `.video` item that was never downloaded has no local file to hand to a
/// player, and its watch page is a full site — chrome, recommendations,
/// tracking cookies — rather than a video. The reader loads the host's own
/// embed instead: it plays inside the pane, and the privacy-enhanced origins
/// (`youtube-nocookie.com`, `player.vimeo.com`) keep the visit out of the
/// host's ad profile.
enum VideoEmbed {
    /// Embed URL for a source/ID pair recorded at capture time.
    /// Unknown sources and IDs carrying anything but the characters real IDs
    /// use return nil, so nothing untrusted is pasted into a URL path.
    static func embedURL(source: String, id: String) -> URL? {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty,
              id.allSatisfy({ $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "-" || $0 == "_" })
        else { return nil }

        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "youtube":
            return URL(string: "https://www.youtube-nocookie.com/embed/\(id)")
        case "vimeo":
            return URL(string: "https://player.vimeo.com/video/\(id)")
        default:
            return nil
        }
    }

    /// Source and video ID read straight out of a watch/share URL, for items
    /// captured before the metadata keys existed.
    static func identify(_ url: URL) -> (source: String, id: String)? {
        guard let host = url.host?.lowercased() else { return nil }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let segments = url.pathComponents.filter { $0 != "/" }

        switch bareHost {
        case "youtu.be":
            return segments.first.map { ("youtube", $0) }

        case "youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com":
            if segments.first == "watch" {
                guard let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "v" })?.value else { return nil }
                return ("youtube", v)
            }
            if segments.count >= 2, ["shorts", "live", "embed", "v"].contains(segments[0]) {
                return ("youtube", segments[1])
            }
            return nil

        case "vimeo.com", "player.vimeo.com":
            // vimeo.com/{id}, player.vimeo.com/video/{id}, and the channel /
            // group forms that bury the numeric ID at the end of the path.
            guard let id = segments.last(where: { !$0.isEmpty && $0.allSatisfy(\.isNumber) })
            else { return nil }
            return ("vimeo", id)

        default:
            return nil
        }
    }

    /// The URL a remote video plays at: the host's embed when the host is one
    /// we know, otherwise the page itself — a Twitch clip or an unrecognized
    /// host is still better served live than not at all.
    static func playbackURL(for url: URL, videoSource: String?, videoID: String?) -> URL {
        if let videoSource, let videoID,
           let embed = embedURL(source: videoSource, id: videoID) {
            return embed
        }
        if let parsed = identify(url),
           let embed = embedURL(source: parsed.source, id: parsed.id) {
            return embed
        }
        return url
    }

    /// The playable URL for a video whose file isn't on this machine, or nil
    /// when it has no web page to play (a local capture, or a source URL that
    /// isn't http(s)). Callers add the "no local file" test themselves, since
    /// what counts as local differs between the desktop reader and the mobile
    /// one.
    static func remoteURL(sourceURL: String?, videoSource: String?, videoID: String?) -> URL? {
        guard let url = resolvedSourceURL(from: sourceURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return playbackURL(for: url, videoSource: videoSource, videoID: videoID)
    }
}

/// Canonical host for matching an item's source URL against a `FeedSource.domain`.
/// Accepts either a full URL or a bare domain and always answers the lowercased
/// host with any leading "www." removed, so both sides of the comparison agree.
func normalizedDomain(_ value: String) -> String {
    let host = (resolvedSourceURL(from: value)?.host ?? value).lowercased()
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}
