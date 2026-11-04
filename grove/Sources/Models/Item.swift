import Foundation
import SQLiteData

enum ItemType: String, Codable, QueryBindable {
    case article
    case codebase
    case video
    case note
    case courseLecture

    var iconName: String {
        switch self {
        case .article: "doc.richtext"
        case .codebase: "terminal"
        case .video: "play.rectangle"
        case .note: "note.text"
        case .courseLecture: "graduationcap"
        }
    }
}

enum ItemStatus: String, Codable, QueryBindable {
    case inbox
    case queued
    case active
    case archived
    case dismissed
}

/// `boardID` is the item's only foreign key, which is what lets a shared
/// board carry its items along with it.
@Table("items")
struct Item: Hashable, Identifiable, Sendable {
    let id: UUID
    var title: String = ""
    var type: ItemType = .note
    var status: ItemStatus = .inbox
    var sourceURL: String?
    var content: String?
    var engagementScore: Float = 0
    @Column(as: [String: String].JSONRepresentation.self)
    var metadata: [String: String] = [:]
    var createdAt: Date = .now
    var updatedAt: Date = .now
    /// Inbox defer queue ("Read Later").
    var readLaterUntil: Date?
    var lastResurfacedAt: Date?
    var resurfaceIntervalDays: Int = 7
    var resurfaceCount: Int = 0
    var lastEngagedAt: Date?
    var isResurfacingPaused: Bool = false
    var boardID: Board.ID?
}

extension Item {
    init(title: String, type: ItemType) {
        self.init(id: UUID(), title: title, type: type)
    }

    // MARK: - Video

    /// Runtime of a video item as `m:ss` (or `h:mm:ss`), when its length is
    /// known. Written in seconds — fractional for local files, whole numbers
    /// from a host's oEmbed data — so both forms are parsed as a Double.
    var videoDurationLabel: String? {
        guard type == .video,
              let raw = metadata["videoDuration"],
              let seconds = Double(raw),
              seconds.isFinite, seconds >= 1 else { return nil }
        return seconds.formattedTimestamp
    }

    // MARK: - Documents

    /// True when what this item points at is a PDF rather than a web page.
    ///
    /// The capture path and the metadata enricher both record the format
    /// explicitly; the URL check is the fallback for items saved before they
    /// did, so a legacy `.pdf` link still opens in the document reader.
    var isPDFDocument: Bool {
        if metadata["format"] == "pdf" { return true }
        guard let url = resolvedSourceURL(from: sourceURL) else { return false }
        return url.pathExtension.lowercased() == "pdf"
    }

    // MARK: - Feed / Newsletter

    /// True for any item that originated from a subscribed feed, regardless
    /// of whether it was later kept into the library.
    var isNewsletterIssue: Bool {
        metadata["feedSourceID"] != nil
    }

    /// True for feed-pipeline items the user has not explicitly kept.
    /// These stay out of inbox triage counts and lists.
    var isFeedSuggestion: Bool {
        metadata["isSuggested"] == "true"
    }

    /// Read state for newsletter issues. Opening an issue marks it read;
    /// expiry also marks it read so history stays browsable.
    var isFeedIssueRead: Bool {
        get { metadata["feedRead"] == "true" }
        set { metadata["feedRead"] = newValue ? "true" : nil }
    }

    /// Writing is keeping: any durable artifact (reflection, highlight,
    /// board assignment, connection) promotes a feed suggestion into the
    /// library proper — same effect as the explicit Keep action.
    mutating func promoteFromFeedSuggestionIfNeeded() {
        guard isFeedSuggestion else { return }
        metadata["isSuggested"] = nil
        metadata["suggestionDismissed"] = nil
        isFeedIssueRead = true
        if status == .inbox {
            status = .active
        }
        updatedAt = .now
    }

    /// Whether this item is deferred from inbox triage until a future date.
    var isQueuedForReadLater: Bool {
        guard status == .queued, let until = readLaterUntil else { return false }
        return until > .now
    }

    /// Whether this item should be considered by discussion suggestion generation.
    /// Only article items can opt out; all other types are always included.
    var isIncludedInDiscussionSuggestions: Bool {
        get {
            guard type == .article else { return true }
            return metadata["excludeFromDiscussionSuggestions"] != "true"
        }
        set {
            guard type == .article else { return }
            metadata["excludeFromDiscussionSuggestions"] = newValue ? nil : "true"
        }
    }
}
