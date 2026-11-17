import Foundation

/// Helpers for safely parsing JSON from LLM responses.
/// LLM output often includes markdown fences, trailing text, or malformed JSON.
enum LLMJSONParser {

    /// Attempt to decode a Decodable type from an LLM response string.
    /// Strips markdown code fences, trims whitespace, and handles common issues.
    static func decode<T: Decodable>(_ type: T.Type, from response: String) -> T? {
        let cleaned = stripMarkdownFences(response)

        guard let data = cleaned.data(using: .utf8) else { return nil }

        // Try strict decoding first
        if let result = try? JSONDecoder().decode(type, from: data) {
            return result
        }

        // Try extracting the first JSON object or array from the string
        if let extracted = extractJSON(from: cleaned),
           let extractedData = extracted.data(using: .utf8),
           let result = try? JSONDecoder().decode(type, from: extractedData) {
            return result
        }

        return nil
    }

    /// Parse raw JSON from an LLM response string into an array.
    static func parseArray(from response: String) -> [[String: Any]]? {
        let cleaned = stripMarkdownFences(response)
        guard let data = cleaned.data(using: .utf8) else { return nil }

        if let result = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return result
        }

        if let extracted = extractJSON(from: cleaned),
           let extractedData = extracted.data(using: .utf8),
           let result = try? JSONSerialization.jsonObject(with: extractedData) as? [[String: Any]] {
            return result
        }

        return nil
    }

    // MARK: - Private

    /// Strip markdown code fences (```json ... ``` or ``` ... ```)
    private static func stripMarkdownFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove opening fence with optional language tag
        if result.hasPrefix("```") {
            if let newlineIndex = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: newlineIndex)...])
            }
        }

        // Remove closing fence
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract the first JSON object ({...}) or array ([...]) from a string.
    private static func extractJSON(from text: String) -> String? {
        // Try object
        if let start = text.firstIndex(of: "{"),
           let extracted = extractBalanced(from: text, startIndex: start, open: "{", close: "}") {
            return extracted
        }

        // Try array
        if let start = text.firstIndex(of: "["),
           let extracted = extractBalanced(from: text, startIndex: start, open: "[", close: "]") {
            return extracted
        }

        return nil
    }

    /// Extract a balanced bracket expression from text.
    private static func extractBalanced(from text: String, startIndex: String.Index, open: Character, close: Character) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = startIndex

        while index < text.endIndex {
            let char = text[index]

            if escaped {
                escaped = false
            } else if char == "\\" && inString {
                escaped = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == open {
                    depth += 1
                } else if char == close {
                    depth -= 1
                    if depth == 0 {
                        return String(text[startIndex...index])
                    }
                }
            }

            index = text.index(after: index)
        }

        return nil
    }
}
