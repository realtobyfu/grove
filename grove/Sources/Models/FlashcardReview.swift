import Foundation
import SQLiteData

enum RecallRating: String, Codable, CaseIterable, Sendable, Identifiable {
    case again
    case hard
    case good
    case easy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .again: "Forgot"
        case .hard: "With effort"
        case .good: "Recalled"
        case .easy: "Easily"
        }
    }

    var order: Int {
        switch self {
        case .again: 0
        case .hard: 1
        case .good: 2
        case .easy: 3
        }
    }
}

/// Append-only learning evidence. Retries reuse `id`, so the primary key
/// deduplicates the event.
@Table("flashcardReviews")
struct FlashcardReview: Hashable, Identifiable, Sendable {
    let id: UUID
    var cardID: UUID
    var cardRevision: Int = 1
    /// Independent edits can share the same numeric revision on two devices.
    /// Only evidence for the winning content fingerprint schedules that card.
    var cardFingerprint: String = ""
    var reviewedAt: Date = .now
    var ratingRaw: String = RecallRating.again.rawValue
    var usedHint: Bool = false
    var readSource: Bool = false
    var sessionID: UUID
}

extension FlashcardReview {
    init(
        id: UUID = UUID(),
        cardID: UUID,
        cardRevision: Int,
        rating: RecallRating,
        usedHint: Bool = false,
        readSource: Bool = false,
        sessionID: UUID,
        reviewedAt: Date = .now,
        cardFingerprint: String = ""
    ) {
        self.init(
            id: id,
            cardID: cardID,
            cardRevision: cardRevision,
            cardFingerprint: cardFingerprint,
            reviewedAt: reviewedAt,
            ratingRaw: rating.rawValue,
            usedHint: usedHint,
            readSource: readSource,
            sessionID: sessionID
        )
    }

    var rating: RecallRating {
        get { RecallRating(rawValue: ratingRaw) ?? .again }
        set { ratingRaw = newValue.rawValue }
    }

    var usedSupport: Bool { usedHint || readSource }
}
