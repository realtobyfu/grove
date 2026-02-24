import Foundation

/// Human-readable label for item types in LLM prompts.
/// Possessive framing for notes ("your note") vs neutral for external content.
extension ItemType {
    var llmLabel: String {
        switch self {
        case .note: "your note"
        case .article: "article"
        case .video: "video"
        case .codebase: "codebase"
        case .courseLecture: "course lecture"
        }
    }
}

/// Shared utilities for building LLM prompt context from Item data.
/// Eliminates duplicated item-description and item-list formatting
/// across ConnectionSuggestionService, SynthesisService, DialecticsService,
/// ReflectionPromptService, SmartNudgeService, and WeeklyDigestService.
enum LLMContextBuilder {
    /// Build a text description of a single item for LLM context.
    /// - Parameters:
    ///   - item: The item to describe.
    ///   - includeContent: Whether to include a content excerpt (default true).
    ///   - contentLimit: Max characters of content to include (default 1000).
    ///   - includeReflections: Whether to include reflection blocks (default true).
    ///   - includeTags: Whether to include tag names (default true).
    /// - Returns: A multi-line string describing the item.
    @MainActor
    static func itemDescription(
        _ item: Item,
        includeContent: Bool = true,
        contentLimit: Int = 1000,
        includeReflections: Bool = true,
        includeTags: Bool = true
    ) -> String {
        var desc = "Title: \(item.title)\nType: \(item.type.rawValue)"

        if includeTags {
            let tags = item.tags.map(\.name).joined(separator: ", ")
            if !tags.isEmpty { desc += "\nTags: \(tags)" }
        }

        if let summary = item.metadata["summary"], !summary.isEmpty {
            desc += "\nSummary: \(summary)"
        }

        if includeContent, let content = item.content, !content.isEmpty {
            desc += "\nContent excerpt: \(String(content.prefix(contentLimit)))"
        }

        if includeReflections && !item.reflections.isEmpty {
            let reflectionTexts = item.reflections
                .sorted { $0.position < $1.position }
                .prefix(5)
                .map { "  - [\($0.blockType.displayName)] \(String($0.content.prefix(200)))" }
                .joined(separator: "\n")
            desc += "\nUser reflections:\n\(reflectionTexts)"
        }

        return desc
    }

    /// Build a numbered list of item descriptions for LLM context.
    /// - Parameters:
    ///   - items: The items to describe.
    ///   - maxItems: Maximum items to include (default 50).
    ///   - includeContent: Whether to include content excerpts.
    /// - Returns: A newline-separated numbered list.
    @MainActor
    static func itemList(
        _ items: [Item],
        maxItems: Int = 50,
        includeContent: Bool = false
    ) -> String {
        items.prefix(maxItems).enumerated().map { index, item in
            let tags = item.tags.map(\.name).joined(separator: ", ")
            let summary = item.metadata["summary"] ?? ""
            return "\(index + 1). (\(item.type.llmLabel)) \"\(item.title)\" [tags: \(tags.isEmpty ? "none" : tags)]\(summary.isEmpty ? "" : " — \(summary)")"
        }.joined(separator: "\n")
    }
}
