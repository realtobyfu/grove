import Foundation

/// Unified text tokenization and keyword extraction.
/// Consolidates duplicate tokenize/stopWords/jaccard logic from
/// and BoardSuggestionEngine.
enum TextTokenizer {
    /// Common English stop words — merged superset from all services.
    static let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "shall", "can", "need", "dare", "ought",
        "used", "to", "of", "in", "for", "on", "with", "at", "by", "from",
        "as", "into", "through", "during", "before", "after", "above", "below",
        "between", "out", "off", "over", "under", "again", "further", "then",
        "once", "here", "there", "when", "where", "why", "how", "all", "each",
        "every", "both", "few", "more", "most", "other", "some", "such", "no",
        "not", "only", "own", "same", "so", "than", "too", "very", "just",
        "because", "but", "and", "or", "if", "while", "that", "this", "these",
        "those", "it", "its", "they", "them", "their", "we", "our", "you",
        "your", "he", "him", "his", "she", "her", "about", "what", "which",
        "who", "whom", "also", "like", "get", "make", "new", "one", "two",
        "say", "way", "man", "old", "see", "now", "any", "back", "come",
        "know", "many", "much", "must", "name", "take", "let"
    ]

    /// Tokenize text into a set of lowercase words, removing stop words and short words.
    /// - Parameters:
    ///   - text: The input text to tokenize.
    ///   - minLength: Minimum character count for a token (default 3).
    /// - Returns: A set of cleaned, lowercase tokens.
    static func tokenize(_ text: String, minLength: Int = 3) -> Set<String> {
        let lowered = text.lowercased()
        let cleaned = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }
        let words = String(cleaned)
            .components(separatedBy: .whitespaces)
            .filter { $0.count >= minLength }
        return Set(words).subtracting(stopWords)
    }

    /// Extract top-K keywords by frequency from text.
    /// - Parameters:
    ///   - text: The input text.
    ///   - topK: Maximum number of keywords to return (default 20).
    /// - Returns: A set of the most frequent non-stop-word tokens.
    static func extractKeywords(from text: String, topK: Int = 20) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        var freq: [String: Int] = [:]
        for word in words {
            freq[word, default: 0] += 1
        }

        return Set(
            freq.sorted { $0.value > $1.value }
                .prefix(topK)
                .map(\.key)
        )
    }

    /// Jaccard similarity between two token sets.
    static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }
}
