import Foundation
import SwiftData

@Model
final class Course {
    var id: UUID = UUID()
    var title: String = ""
    var sourceURL: String?
    var courseDescription: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .nullify) var lectures: [Item] = []
    @Relationship(deleteRule: .nullify) var board: Board?

    /// Ordered lecture IDs — Item.id values in intended sequence.
    /// We maintain order separately since SwiftData relationships are unordered.
    var lectureOrder: [UUID] = []

    init(title: String, sourceURL: String? = nil) {
        self.id = UUID()
        self.title = title
        self.sourceURL = sourceURL
        self.courseDescription = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.lectures = []
        self.board = nil
        self.lectureOrder = []
    }

    // MARK: - Computed Helpers

    /// Lectures sorted by their position in lectureOrder.
    var orderedLectures: [Item] {
        let idToItem = Dictionary(uniqueKeysWithValues: lectures.map { ($0.id, $0) })
        return lectureOrder.compactMap { idToItem[$0] }
    }

    /// Number of lectures marked completed (metadata["completed"] == "true").
    var completedCount: Int {
        lectures.filter { $0.metadata["completed"] == "true" }.count
    }

    /// Total lecture count.
    var totalCount: Int {
        lectures.count
    }

    /// Progress as a fraction 0.0–1.0.
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    /// The next uncompleted lecture in order, if any.
    var nextLecture: Item? {
        orderedLectures.first { $0.metadata["completed"] != "true" }
    }
}
