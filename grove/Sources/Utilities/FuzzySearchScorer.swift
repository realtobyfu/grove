import Foundation

/// Shared fuzzy matching scorer used by search surfaces.
enum FuzzySearchScorer {
    /// Returns a score from 0.0 to 1.0 for how well `normalizedQuery` matches `normalizedText`.
    /// Inputs should already be normalized (typically lowercased) by the caller.
    static func score(normalizedQuery: String, in normalizedText: String) -> Double {
        guard !normalizedQuery.isEmpty, !normalizedText.isEmpty else { return 0 }

        if normalizedText == normalizedQuery { return 1.0 }
        if normalizedText.hasPrefix(normalizedQuery) { return 0.95 }

        if normalizedText.contains(normalizedQuery) {
            if let range = normalizedText.range(of: normalizedQuery) {
                let idx = normalizedText.distance(from: normalizedText.startIndex, to: range.lowerBound)
                if idx == 0 {
                    return 0.9
                }

                let charBefore = normalizedText[normalizedText.index(range.lowerBound, offsetBy: -1)]
                if charBefore == " " || charBefore == "-" || charBefore == "_" || charBefore == "/" {
                    return 0.85
                }

                let positionPenalty = Double(idx) / Double(normalizedText.count) * 0.2
                return max(0.6 - positionPenalty, 0.4)
            }
            return 0.5
        }

        let queryWords = normalizedQuery.split(separator: " ")
        if queryWords.count > 1 {
            let allFound = queryWords.allSatisfy { word in
                normalizedText.contains(word)
            }
            if allFound {
                return 0.55
            }
        }

        let matchScore = subsequenceScore(normalizedQuery, in: normalizedText)
        if matchScore > 0.5 {
            return matchScore * 0.5
        }

        return 0
    }

    private static func subsequenceScore(_ query: String, in text: String) -> Double {
        var queryIdx = query.startIndex
        var textIdx = text.startIndex
        var matched = 0

        while queryIdx < query.endIndex && textIdx < text.endIndex {
            if query[queryIdx] == text[textIdx] {
                matched += 1
                queryIdx = query.index(after: queryIdx)
            }
            textIdx = text.index(after: textIdx)
        }

        return Double(matched) / Double(query.count)
    }
}
