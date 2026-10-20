import CryptoKit
import Foundation
import SwiftData

/// A small, explicitly chosen question with a durable snapshot of its source.
/// Source references are identifiers rather than cascading relationships: a
/// deleted article must not erase the passage a person learned from.
@Model
final class Flashcard {
    var id: UUID = UUID()
    var question: String = ""
    var answer: String = ""
    var hints: [String] = []
    var sourceItemID: UUID?
    var sourceReflectionID: UUID?
    var sourceTitle: String = "Your flashcard"
    var sourceQuote: String?
    var sourceURL: String?
    var sourceLocator: String?
    var boardIDs: [UUID] = []
    var revision: Int = 1
    /// Changes only with the question/answer/hints, not suspension or metadata.
    var revisionStartedAt: Date = Date.now
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isSuspended: Bool = false
    var dueAt: Date = Date.now
    /// Detects content changes even when a caller edits a bound model directly.
    var revisionFingerprint: String = ""
    /// A tombstone preserves review history and makes deletion merge safely.
    var deletedAt: Date?

    init(
        question: String,
        answer: String,
        sourceItem: Item? = nil,
        sourceQuote: String? = nil,
        sourceReflectionID: UUID? = nil,
        hints: [String] = []
    ) {
        self.question = question
        self.answer = answer
        self.hints = hints
        self.sourceItemID = sourceItem?.id
        self.sourceReflectionID = sourceReflectionID
        self.sourceTitle = sourceItem?.title ?? "Your flashcard"
        self.sourceURL = sourceItem?.sourceURL
        self.boardIDs = Array(Set(sourceItem?.boards.map(\.id) ?? []))
            .sorted { $0.uuidString < $1.uuidString }

        let reflection = sourceItem?.reflections.first { $0.id == sourceReflectionID }
        let snapshot = sourceQuote ?? reflection?.highlight
            ?? reflection?.content
            ?? (sourceItem?.type == .note ? sourceItem?.content : nil)
        self.sourceQuote = snapshot?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timestamp = reflection?.videoTimestamp {
            self.sourceLocator = "video:\(timestamp)"
        }
        self.revisionFingerprint = Self.fingerprint(question: question, answer: answer, hints: hints)
        self.revisionStartedAt = self.createdAt
    }

    static func fingerprint(question: String, answer: String, hints: [String]) -> String {
        // JSON preserves field boundaries; separators in a person's text cannot
        // accidentally make two different questions share a revision.
        let values = [question, answer] + hints
        let data = (try? JSONEncoder().encode(values)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
