import Foundation

// MARK: - LLM Context Candidate

/// A context snippet sent to the LLM for conversation starter generation.
struct StarterLLMContextCandidate {
    let id: String
    let summary: String
    let clusterTag: String?
    let itemIDs: [UUID]
    let boardIDs: [UUID]
}

// MARK: - StarterLLMGenerator

/// Constructs LLM prompts for conversation starter generation and parses the responses
/// into `PromptBubble` objects.
enum StarterLLMGenerator {

    // MARK: - LLM Generation

    /// Calls the LLM provider to generate conversation starters from the given context.
    /// Returns nil if candidates are empty or the LLM call fails.
    @MainActor
    static func generate(
        context: StarterContext,
        didShowClusterBubble: Bool,
        provider: LLMProvider
    ) async -> [PromptBubble]? {
        let candidates = buildCandidates(from: context, didShowClusterBubble: didShowClusterBubble)
        guard !candidates.isEmpty else {
            return nil
        }

        let systemPrompt = """
        You are a philosophical thinking partner that helps users reflect on their knowledge base.
        Given context snippets, generate up to 3 engaging conversation starters.

        Rules:
        - Each starter is a single, thought-provoking question or prompt (1-2 sentences)
        - Tone: curious, intellectually engaged, not generic
        - Each starter has a short label: REVISIT, EXPLORE, RESOLVE, REFLECT, SYNTHESIZE, or ORGANIZE
        - If a starter is tied to one of the snippets below, include its exact `context_id`
        - If a starter is general and not tied to a specific snippet, use `context_id` = "general"
        - Items annotated "(your note)" are the user's own writing — use "you wrote" framing.
        - Items annotated "(article)", "(video)", etc. are external content — use "that article" or "the video" framing.
        - Return ONLY valid JSON. No markdown fences, no explanation.

        Output format:
        [{"prompt": "...", "label": "REVISIT", "context_id": "stale_0"}]
        """

        var userLines: [String] = ["Context snippets (with stable IDs):"]
        userLines.append(contentsOf: candidates.map { "- \($0.id): \($0.summary)" })
        let userMessage = userLines.joined(separator: "\n")

        guard let result = await provider.complete(
            system: systemPrompt,
            user: userMessage,
            service: "conversationStarter"
        ) else {
            return nil
        }

        return parseResponse(result.content, candidates: candidates)
    }

    // MARK: - Candidate Building

    /// Builds LLM context candidates from the aggregated starter context.
    @MainActor
    static func buildCandidates(
        from context: StarterContext,
        didShowClusterBubble: Bool
    ) -> [StarterLLMContextCandidate] {
        var candidates: [StarterLLMContextCandidate] = []

        if !context.recentItems.isEmpty {
            let recentItems = Array(context.recentItems.prefix(6))
            let titles = recentItems.prefix(4).map { "(\($0.type.llmLabel)) \"\($0.title)\"" }.joined(separator: ", ")
            candidates.append(StarterLLMContextCandidate(
                id: "recent_items",
                summary: "Recently saved items (last 7 days): \(titles)",
                clusterTag: nil,
                itemIDs: recentItems.map(\.id),
                boardIDs: StarterContextBuilder.boardIDs(for: recentItems)
            ))
        }

        for (index, item) in context.staleItems.prefix(2).enumerated() {
            candidates.append(StarterLLMContextCandidate(
                id: "stale_\(index)",
                summary: "Stale item not touched in 30+ days: (\(item.type.llmLabel)) \"\(item.title)\"",
                clusterTag: nil,
                itemIDs: [item.id],
                boardIDs: StarterContextBuilder.boardIDs(for: [item])
            ))
        }

        if let tag = context.topRecentTag, context.topRecentTagCount >= 2 {
            let recentTaggedItems = Array(
                context.recentItems
                    .filter { item in item.tags.contains(where: { $0.name == tag }) }
                    .prefix(6)
            )
            if !recentTaggedItems.isEmpty {
                let titles = recentTaggedItems.prefix(4).map { "(\($0.type.llmLabel)) \"\($0.title)\"" }.joined(separator: ", ")
                candidates.append(StarterLLMContextCandidate(
                    id: "recent_tag",
                    summary: "Recent cluster for tag \"\(tag)\" (\(context.topRecentTagCount) items): \(titles)",
                    clusterTag: nil,
                    itemIDs: recentTaggedItems.map(\.id),
                    boardIDs: StarterContextBuilder.boardIDs(for: recentTaggedItems)
                ))
            }
        }

        let contradictionItems = Array(context.contradictionItems.prefix(2))
        if !contradictionItems.isEmpty {
            let titles = contradictionItems.map { "(\($0.type.llmLabel)) \"\($0.title)\"" }.joined(separator: " vs ")
            candidates.append(StarterLLMContextCandidate(
                id: "contradiction",
                summary: "Items with contradictions: \(titles)",
                clusterTag: nil,
                itemIDs: contradictionItems.map(\.id),
                boardIDs: StarterContextBuilder.boardIDs(for: contradictionItems)
            ))
        }

        if let cluster = context.unboardedCluster, !didShowClusterBubble {
            let titles = cluster.items.prefix(4).map { "(\($0.type.llmLabel)) \"\($0.title)\"" }.joined(separator: ", ")
            candidates.append(StarterLLMContextCandidate(
                id: "organize_cluster",
                summary: "Unboarded items sharing tag \"\(cluster.sharedTag)\" (\(cluster.count) items): \(titles)",
                clusterTag: cluster.sharedTag,
                itemIDs: cluster.items.map(\.id),
                boardIDs: []
            ))
        }

        return candidates
    }

    // MARK: - Response Parsing

    /// Parses the raw LLM response string into an array of `PromptBubble` objects.
    static func parseResponse(_ raw: String, candidates: [StarterLLMContextCandidate]) -> [PromptBubble]? {
        // Strip markdown fences if present
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = cleaned.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([LLMBubblePayload].self, from: data) else {
            return nil
        }

        let candidateLookup = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })

        let parsed = decoded.compactMap { payload -> PromptBubble? in
            let prompt = payload.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = payload.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, !label.isEmpty else { return nil }

            let candidate = payload.contextID.flatMap { candidateLookup[$0] }
            return PromptBubble(
                prompt: prompt,
                label: label,
                clusterTag: candidate?.clusterTag,
                clusterItemIDs: candidate?.itemIDs ?? [],
                boardIDs: candidate?.boardIDs ?? []
            )
        }

        return parsed.isEmpty ? nil : Array(parsed.prefix(3))
    }

    // MARK: - Private Types

    private struct LLMBubblePayload: Decodable {
        let prompt: String
        let label: String
        let contextID: String?

        private enum CodingKeys: String, CodingKey {
            case prompt
            case label
            case contextID = "context_id"
        }
    }
}
