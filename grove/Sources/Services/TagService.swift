import Foundation
import SQLiteData

/// Represents a suggestion to merge two near-duplicate tags
struct TagMergeSuggestion: Identifiable {
    let id = UUID()
    let tag1: TagGraph
    let tag2: TagGraph
    let similarity: Double
    let reason: String
}

/// Represents a suggestion for parent-child hierarchy between tags
struct TagHierarchySuggestion: Identifiable {
    let id = UUID()
    let parentTag: TagGraph
    let childTag: TagGraph
    let reason: String
}

/// Protocol for tag service.
@MainActor
protocol TagServiceProtocol {
    func mergeTags(keep: Tag.ID, remove: Tag.ID)
    func findMergeSuggestions(from tags: [TagGraph]) -> [TagMergeSuggestion]
}

/// Service for tag analysis: duplicate detection, merging, hierarchy suggestions, and improved clustering
@MainActor
@Observable
final class TagService: TagServiceProtocol {
    private let database: any DatabaseWriter

    init(database: any DatabaseWriter = AppDatabase.current) {
        self.database = database
    }

    // MARK: - Near-Duplicate Detection

    /// Find tags that are near-duplicates based on string similarity
    func findMergeSuggestions(from tags: [TagGraph]) -> [TagMergeSuggestion] {
        var suggestions: [TagMergeSuggestion] = []
        let seen = NSMutableSet()

        for i in 0..<tags.count {
            for j in (i + 1)..<tags.count {
                let tag1 = tags[i]
                let tag2 = tags[j]

                // Skip if already has a parent-child relationship
                if tag1.parentTag?.id == tag2.id || tag2.parentTag?.id == tag1.id {
                    continue
                }

                let pairKey = [tag1.id.uuidString, tag2.id.uuidString].sorted().joined(separator: "-")
                if seen.contains(pairKey) { continue }

                let sim = Self.nameSimilarity(tag1.name, tag2.name)
                if sim >= AppConstants.Scoring.tagMergeSimilarity {
                    let reason = describeSimReason(tag1.name, tag2.name)
                    suggestions.append(TagMergeSuggestion(
                        tag1: tag1,
                        tag2: tag2,
                        similarity: sim,
                        reason: reason
                    ))
                    seen.add(pairKey)
                }
            }
        }

        return suggestions.sorted { $0.similarity > $1.similarity }
    }

    /// Compute string similarity between two tag names using normalized edit distance
    nonisolated static func nameSimilarity(_ a: String, _ b: String) -> Double {
        let s1 = normalize(a)
        let s2 = normalize(b)

        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }

        let distance = levenshteinDistance(s1, s2)
        let maxLen = max(s1.count, s2.count)
        return 1.0 - Double(distance) / Double(maxLen)
    }

    /// Normalize a tag name for comparison: lowercase, strip separators
    nonisolated static func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    /// Levenshtein edit distance
    nonisolated static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,      // deletion
                    curr[j - 1] + 1,   // insertion
                    prev[j - 1] + cost // substitution
                )
            }
            prev = curr
        }

        return prev[n]
    }

    private func describeSimReason(_ a: String, _ b: String) -> String {
        let na = Self.normalize(a)
        let nb = Self.normalize(b)
        if na == nb {
            return "Same name with different separators"
        }
        if na.contains(nb) || nb.contains(na) {
            return "One name contains the other"
        }
        return "Very similar names"
    }

    // MARK: - Tag Merge

    /// Merge tag2 into tag1: moves all items from tag2 to tag1, then deletes tag2
    ///
    /// A join row's ID comes from its pair, so a link can't be repointed by
    /// changing `tagID`. Each gets a new row here, ignored if `keep` is already
    /// linked, and the old rows go with the tag.
    func mergeTags(keep keepID: Tag.ID, remove removeID: Tag.ID) {
        database.attempt { db in
            // A suggestion can outlive either tag.
            guard let keep = try Tag.find(keepID).fetchOne(db),
                  let remove = try Tag.find(removeID).fetchOne(db) else { return }

            // Transfer all items from 'remove' to 'keep'
            let itemIDs = try ItemTag.where { $0.tagID.eq(removeID) }.select(\.itemID).fetchAll(db)
            for itemID in itemIDs {
                try Item.addTag(keepID, toItem: itemID, in: db)
            }

            // Transfer child tags, before the delete clears them
            try Tag.where { $0.parentTagID.eq(removeID) }
                .update { $0.parentTagID = #bind(keepID) }
                .execute(db)

            // Transfer smart board rules
            let boardIDs = try BoardSmartRuleTag.where { $0.tagID.eq(removeID) }.select(\.boardID).fetchAll(db)
            for boardID in boardIDs {
                try Board.addSmartRuleTag(keepID, toBoard: boardID, in: db)
            }

            // If remove had a parent, keep that hierarchy for keep (if keep has no parent)
            if let removeParentID = remove.parentTagID, keep.parentTagID == nil {
                try Tag.modify(keepID, in: db) { $0.parentTagID = removeParentID }
            }

            try Tag.find(removeID).delete().execute(db)
        }
    }

    // MARK: - Hierarchy Detection

    /// Detect potential parent-child relationships among tags
    func findHierarchySuggestions(from tags: [TagGraph]) -> [TagHierarchySuggestion] {
        var suggestions: [TagHierarchySuggestion] = []

        for i in 0..<tags.count {
            for j in 0..<tags.count {
                guard i != j else { continue }
                let potentialParent = tags[i]
                let potentialChild = tags[j]

                // Skip if already in a hierarchy
                if potentialChild.parentTag != nil { continue }

                // Check if child name contains/starts with parent name (e.g., "SwiftUI" contains "Swift")
                if let reason = checkHierarchyRelationship(parent: potentialParent, child: potentialChild) {
                    suggestions.append(TagHierarchySuggestion(
                        parentTag: potentialParent,
                        childTag: potentialChild,
                        reason: reason
                    ))
                }
            }
        }

        // Deduplicate: only keep the best parent for each child
        var bestForChild: [UUID: TagHierarchySuggestion] = [:]
        for suggestion in suggestions {
            let childID = suggestion.childTag.id
            if let existing = bestForChild[childID] {
                // Prefer longer parent name (more specific parent)
                if suggestion.parentTag.name.count > existing.parentTag.name.count {
                    bestForChild[childID] = suggestion
                }
            } else {
                bestForChild[childID] = suggestion
            }
        }

        return Array(bestForChild.values).sorted { $0.childTag.name < $1.childTag.name }
    }

    private func checkHierarchyRelationship(parent: TagGraph, child: TagGraph) -> String? {
        let parentLower = parent.name.lowercased()
        let childLower = child.name.lowercased()

        // Child name must be longer than parent (child is more specific)
        guard childLower.count > parentLower.count else { return nil }

        // The parent name must not be too short (avoid single-char matches)
        guard parentLower.count >= 3 else { return nil }

        // Child starts with parent name: e.g., "SwiftUI" starts with "Swift"
        if childLower.hasPrefix(parentLower) {
            return "\"\(child.name)\" starts with \"\(parent.name)\""
        }

        // Child contains parent as a word: e.g., "Swift Concurrency" contains "Swift"
        let childWords = childLower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let parentWords = parentLower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }

        if parentWords.count == 1 && childWords.contains(parentLower) && childWords.count > 1 {
            return "\"\(child.name)\" contains \"\(parent.name)\" as a component"
        }

        // Co-occurrence: if parent's items are a superset of child's items (child is more specific)
        if !child.items.isEmpty && !parent.items.isEmpty {
            let childItemIDs = Set(child.items.map(\.id))
            let parentItemIDs = Set(parent.items.map(\.id))
            if childItemIDs.isSubset(of: parentItemIDs) && childItemIDs.count < parentItemIDs.count {
                return "All items tagged \"\(child.name)\" are also tagged \"\(parent.name)\""
            }
        }

        return nil
    }

    /// Apply a hierarchy suggestion
    func applyHierarchy(parent parentID: Tag.ID, child childID: Tag.ID) {
        database.attempt { db in
            try Tag.modify(childID, in: db) { $0.parentTagID = parentID }
        }
    }

    /// Remove a hierarchy relationship
    func removeHierarchy(child childID: Tag.ID) {
        database.attempt { db in
            try Tag.modify(childID, in: db) { $0.parentTagID = nil }
        }
    }

    // MARK: - Trend Tracking

    /// Update trend data for all tags — call periodically (e.g., on app launch)
    func updateTrends(for tags: [TagGraph]) {
        let now = Date()
        database.attempt { db in
            for tag in tags {
                // Only update if we haven't calculated recently (within 24 hours)
                if let lastCalc = tag.trendCalculatedAt,
                   now.timeIntervalSince(lastCalc) < 86400 {
                    continue
                }
                try Tag.modify(tag.id, in: db) {
                    $0.previousItemCount = tag.items.count
                    $0.trendCalculatedAt = now
                }
            }
        }
    }

    // MARK: - Improved Clustering (co-occurrence based)

    /// Compute co-occurrence matrix for tags based on shared items
    nonisolated static func tagCooccurrence(tags: [TagGraph]) -> [UUID: [UUID: Int]] {
        var matrix: [UUID: [UUID: Int]] = [:]
        for tag in tags {
            let itemIDs = Set(tag.items.map(\.id))
            for otherTag in tags where otherTag.id != tag.id {
                let otherItemIDs = Set(otherTag.items.map(\.id))
                let overlap = itemIDs.intersection(otherItemIDs).count
                if overlap > 0 {
                    matrix[tag.id, default: [:]][otherTag.id] = overlap
                }
            }
        }
        return matrix
    }

}
