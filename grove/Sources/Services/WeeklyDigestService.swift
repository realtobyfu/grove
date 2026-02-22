import Foundation
import SwiftData

/// Protocol for testability.
protocol WeeklyDigestServiceProtocol {
    @MainActor func generateDigest(context: ModelContext) async -> Item?
}

/// LLM-backed weekly digest generator. Gathers items added, reflections written,
/// connections formed, and board activity over the past 7 days, then sends to LLM
/// for a 150-250 word summary. Falls back to a local heuristic digest if LLM is
/// unavailable. Creates the digest as a special Item with type .note and metadata
/// digest=true.
final class WeeklyDigestService: WeeklyDigestServiceProtocol {
    private let provider: LLMProvider

    init(provider: LLMProvider = LLMServiceConfig.makeProvider()) {
        self.provider = provider
    }

    @MainActor func generateDigest(context: ModelContext) async -> Item? {
        guard EntitlementService.shared.isPro else { return nil }
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -AppConstants.Days.recent, to: .now) ?? .now

        let allItems = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let boards = (try? context.fetch(FetchDescriptor<Board>())) ?? []

        // Items added this week (excluding dismissed)
        let newItems = allItems.filter { $0.createdAt > sevenDaysAgo && $0.status != .dismissed }

        // Reflections written this week (across all items)
        let allReflections = allItems.flatMap { $0.reflections }
        let newReflections = allReflections.filter { $0.createdAt > sevenDaysAgo }

        // Connections formed this week
        let allConnections = allItems.flatMap { $0.outgoingConnections }
        let newConnections = allConnections.filter { $0.createdAt > sevenDaysAgo }

        // Activity threshold: at least 2 items added or 1 reflection written
        guard newItems.count >= AppConstants.Activity.digestMinItems || newReflections.count >= AppConstants.Activity.digestMinReflections else { return nil }

        // Generate digest content
        let markdownContent: String
        let isLLMGenerated: Bool

        if LLMServiceConfig.isConfigured {
            let systemPrompt = buildSystemPrompt()
            let userPrompt = buildUserPrompt(
                newItems: newItems,
                newReflections: newReflections,
                newConnections: newConnections,
                boards: boards,
                allItems: allItems
            )

            if let result = await provider.complete(system: systemPrompt, user: userPrompt, service: "digest") {
                markdownContent = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
                isLLMGenerated = true
            } else {
                markdownContent = buildLocalDigest(
                    newItems: newItems,
                    newReflections: newReflections,
                    newConnections: newConnections,
                    boards: boards
                )
                isLLMGenerated = false
            }
        } else {
            markdownContent = buildLocalDigest(
                newItems: newItems,
                newReflections: newReflections,
                newConnections: newConnections,
                boards: boards
            )
            isLLMGenerated = false
        }

        // Create digest item
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        let dateString = dateFormatter.string(from: .now)
        let title = "Weekly Digest — \(dateString)"

        let item = Item(title: title, type: .note)
        item.status = .active
        item.content = markdownContent
        item.metadata["digest"] = "true"
        item.metadata["isAIGenerated"] = isLLMGenerated ? "true" : "false"
        item.metadata["digestDate"] = ISO8601DateFormatter().string(from: .now)

        context.insert(item)
        try? context.save()

        // Update last generated timestamp
        NudgeSettings.digestLastGeneratedAt = Date.now.timeIntervalSince1970

        return item
    }

    // MARK: - LLM Prompts

    private func buildSystemPrompt() -> String {
        """
        You are a learning assistant for a personal knowledge management tool called Grove.
        The user saves articles, videos, notes, and lectures, then reflects on them.

        Generate a weekly digest summarizing their learning activity. The digest should be
        150-250 words in markdown format. Include:

        1. **What was added** — count and highlights of new items
        2. **What was reflected on** — items that received reflection blocks
        3. **Knowledge gaps identified** — topics with items but no reflections, or areas that could use more depth
        4. **Suggested focus** — one specific recommendation for the coming week

        Rules:
        - Reference specific item titles using [[wiki-link]] syntax
        - Be warm but concise — this is a summary, not an essay
        - Highlight interesting patterns or connections the user might not have noticed
        - If items cluster around a topic, mention that theme
        - Return plain markdown only, no JSON wrapping
        """
    }

    @MainActor private func buildUserPrompt(
        newItems: [Item],
        newReflections: [ReflectionBlock],
        newConnections: [Connection],
        boards: [Board],
        allItems: [Item]
    ) -> String {
        var parts: [String] = []

        // Items added this week
        let itemList = LLMContextBuilder.itemList(Array(newItems.prefix(20)), maxItems: 20)
        parts.append("ITEMS ADDED THIS WEEK (\(newItems.count) total):\n\(itemList)")

        // Reflections written
        if !newReflections.isEmpty {
            let reflectionLines = newReflections.prefix(15).map { block in
                let itemTitle = block.item?.title ?? "Unknown"
                return "- [\(block.blockType.displayName)] on \"\(itemTitle)\": \(String(block.content.prefix(80)))"
            }.joined(separator: "\n")
            parts.append("REFLECTIONS WRITTEN THIS WEEK (\(newReflections.count) total):\n\(reflectionLines)")
        }

        // Connections formed
        if !newConnections.isEmpty {
            parts.append("CONNECTIONS FORMED: \(newConnections.count)")
        }

        // Most active boards
        let boardActivity = boards.compactMap { board -> (String, Int)? in
            let weekItems = board.items.filter { $0.createdAt > (Calendar.current.date(byAdding: .day, value: -AppConstants.Days.recent, to: .now) ?? .now) }
            guard weekItems.count > 0 else { return nil }
            return (board.title, weekItems.count)
        }.sorted { $0.1 > $1.1 }

        if !boardActivity.isEmpty {
            let boardLines = boardActivity.prefix(5).map { "- \($0.0): \($0.1) new items" }.joined(separator: "\n")
            parts.append("MOST ACTIVE BOARDS:\n\(boardLines)")
        }

        // Overall stats
        let totalItems = allItems.count
        let reflectedCount = allItems.filter { !$0.reflections.isEmpty }.count
        let inboxCount = allItems.filter { $0.status == .inbox }.count
        parts.append("OVERALL: \(totalItems) total items, \(reflectedCount) reflected, \(inboxCount) in inbox")

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Local Fallback

    private func buildLocalDigest(
        newItems: [Item],
        newReflections: [ReflectionBlock],
        newConnections: [Connection],
        boards: [Board]
    ) -> String {
        var lines: [String] = []

        lines.append("## This Week in Your Grove\n")

        // What was added
        lines.append("### Added")
        lines.append("You saved **\(newItems.count) items** this week.")
        let byType = Dictionary(grouping: newItems, by: { $0.type })
        let typeSummary = byType.map { "\($0.value.count) \($0.key.rawValue)\($0.value.count == 1 ? "" : "s")" }
            .joined(separator: ", ")
        if !typeSummary.isEmpty {
            lines.append("Breakdown: \(typeSummary).")
        }
        let highlights = newItems.prefix(3).map { "[[\($0.title)]]" }.joined(separator: ", ")
        if !highlights.isEmpty {
            lines.append("Highlights: \(highlights).")
        }

        // What was reflected on
        if !newReflections.isEmpty {
            lines.append("\n### Reflected")
            let reflectedItemTitles = Set(newReflections.compactMap { $0.item?.title })
            lines.append("You wrote **\(newReflections.count) reflection\(newReflections.count == 1 ? "" : "s")** across \(reflectedItemTitles.count) item\(reflectedItemTitles.count == 1 ? "" : "s").")
            let topReflected = reflectedItemTitles.prefix(3).map { "[[\($0)]]" }.joined(separator: ", ")
            if !topReflected.isEmpty {
                lines.append("Items: \(topReflected).")
            }
        }

        // Connections
        if !newConnections.isEmpty {
            lines.append("\n### Connected")
            lines.append("You formed **\(newConnections.count) connection\(newConnections.count == 1 ? "" : "s")** between items.")
        }

        // Knowledge gaps
        let unreflected = newItems.filter { $0.reflections.isEmpty }
        if unreflected.count > 0 {
            lines.append("\n### Gaps")
            lines.append("\(unreflected.count) of your new items have no reflections yet.")
            let gapHighlights = unreflected.prefix(2).map { "[[\($0.title)]]" }.joined(separator: " and ")
            if !gapHighlights.isEmpty {
                lines.append("Consider reflecting on \(gapHighlights).")
            }
        }

        return lines.joined(separator: "\n")
    }
}
