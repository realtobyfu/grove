import CryptoKit
import Foundation
import SQLiteData

/// Source references are identifiers rather than foreign keys: a deleted
/// article must not erase the passage a person learned from.
@Table("flashcards")
struct Flashcard: Hashable, Identifiable, Sendable {
    let id: UUID
    var question: String = ""
    var answer: String = ""
    @Column(as: [String].JSONRepresentation.self)
    var hints: [String] = []
    var sourceItemID: UUID?
    var sourceReflectionID: UUID?
    var sourceTitle: String = "Your flashcard"
    var sourceQuote: String?
    var sourceURL: String?
    var sourceLocator: String?
    @Column(as: [UUID].JSONRepresentation.self)
    var boardIDs: [UUID] = []
    var revision: Int = 1
    /// Changes only with the question/answer/hints, not suspension or metadata.
    var revisionStartedAt: Date = .now
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var isSuspended: Bool = false
    var dueAt: Date = .now
    /// Detects content changes even when a caller edits a card directly.
    var revisionFingerprint: String = ""
    /// A tombstone preserves review history and makes deletion merge safely.
    var deletedAt: Date?
}

extension Flashcard {
    init(
        question: String,
        answer: String,
        sourceItem: ItemGraph? = nil,
        sourceQuote: String? = nil,
        sourceReflectionID: UUID? = nil,
        hints: [String] = []
    ) {
        let now = Date.now
        let reflection = sourceItem?.reflections.first { $0.id == sourceReflectionID }
        let snapshot = sourceQuote ?? reflection?.highlight
            ?? reflection?.content
            ?? (sourceItem?.type == .note ? sourceItem?.content : nil)
        self.init(
            id: UUID(),
            question: question,
            answer: answer,
            hints: hints,
            sourceItemID: sourceItem?.id,
            sourceReflectionID: sourceReflectionID,
            sourceTitle: sourceItem?.title ?? "Your flashcard",
            sourceQuote: snapshot?.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURL: sourceItem?.sourceURL,
            sourceLocator: reflection?.videoTimestamp.map { "video:\($0)" },
            boardIDs: sourceItem?.board.map { [$0.id] } ?? [],
            revisionStartedAt: now,
            createdAt: now,
            updatedAt: now,
            dueAt: now,
            revisionFingerprint: Self.fingerprint(question: question, answer: answer, hints: hints)
        )
    }

    static func fingerprint(question: String, answer: String, hints: [String]) -> String {
        // JSON preserves field boundaries; separators in a person's text cannot
        // accidentally make two different questions share a revision.
        let values = [question, answer] + hints
        let data = (try? JSONEncoder().encode(values)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
