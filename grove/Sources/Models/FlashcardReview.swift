import Foundation
import SwiftData

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

/// Append-only learning evidence. Retries reuse `id`; model reconciliation
/// deduplicates that event key rather than relying on CloudKit uniqueness.
@Model
final class UserFlashcardReview {
    var id: UUID = UUID()
    var cardID: UUID = UUID()
    var cardRevision: Int = 1
    /// Independent edits can share the same numeric revision on two devices.
    /// Only evidence for the winning content fingerprint schedules that card.
    var cardFingerprint: String = ""
    var reviewedAt: Date = Date.now
    var ratingRaw: String = RecallRating.again.rawValue
    var usedHint: Bool = false
    var readSource: Bool = false
    var sessionID: UUID = UUID()

    var rating: RecallRating {
        get { RecallRating(rawValue: ratingRaw) ?? .again }
        set { ratingRaw = newValue.rawValue }
    }

    var usedSupport: Bool { usedHint || readSource }

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
        self.id = id
        self.cardID = cardID
        self.cardRevision = cardRevision
        self.cardFingerprint = cardFingerprint
        self.ratingRaw = rating.rawValue
        self.usedHint = usedHint
        self.readSource = readSource
        self.sessionID = sessionID
        self.reviewedAt = reviewedAt
    }
}

/// The stored entity is named `UserFlashcardReview` so it sorts after every 2.0 entity.
/// Read "Migration Limits" in SharedModelContainer.swift before adding a model.
typealias FlashcardReview = UserFlashcardReview
