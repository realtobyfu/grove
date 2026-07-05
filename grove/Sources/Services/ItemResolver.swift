import Foundation

/// Resolves an LLM-provided item reference (UUID string or title) to an Item.
/// LLMs paraphrase titles, so exact matching silently fails — this applies
/// progressively looser matching and only returns fuzzy results when unambiguous.
@MainActor
enum ItemResolver {
    /// Resolve a reference against a set of items.
    /// Order: UUID → exact title → normalized title → unique substring match.
    static func resolve(_ reference: String, in items: [Item]) -> Item? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let uuid = UUID(uuidString: trimmed) {
            return items.first(where: { $0.id == uuid })
        }

        let lowered = trimmed.lowercased()
        if let exact = items.first(where: { $0.title.lowercased() == lowered }) {
            return exact
        }

        let normalizedRef = normalize(trimmed)
        guard !normalizedRef.isEmpty else { return nil }
        if let normalized = items.first(where: { normalize($0.title) == normalizedRef }) {
            return normalized
        }

        // Substring match, only when it identifies a single item
        let contains = items.filter {
            let title = normalize($0.title)
            return title.contains(normalizedRef) || normalizedRef.contains(title)
        }
        return contains.count == 1 ? contains.first : nil
    }

    /// Lowercase, strip punctuation, collapse whitespace.
    static func normalize(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let stripped = String(text.lowercased().unicodeScalars.filter { allowed.contains($0) })
        return stripped
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
