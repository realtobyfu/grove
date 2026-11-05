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
        You help someone think about what they have been reading and saving.
        Given context snippets from their knowledge base, generate up to 3 conversation starters.

        Rules:
        - Ground every starter in the substance under a title — the summary, excerpt, or
          note text quoted after the em dash. A title is a label, not a claim: never
          restate one back as something the person said or argued, and never infer what a
          piece is about from its wording.
        - Skip any snippet you have nothing specific to say about. One good starter, or an
          empty list, beats padding to three.
        - Keep it concrete and answerable: ask about a specific claim, decision, or connection.
          The person should be able to start answering immediately from what they read.
          Never reach for grand abstractions ("deeper philosophical divide", "broader implications
          for humanity") — they read as filler.
        - Never ask which part they find interesting, compelling, or most striking. That hands
          the thinking back to them. Ask about the substance itself.
        - Plain, direct language. One question or prompt, 1-2 sentences.
        - If a snippet describes two items "in tension" but the tension is superficial or the
          items are simply about different topics, skip that snippet rather than forcing a question.
        - `label` must be exactly one of: REVISIT, EXPLORE, RESOLVE, REFLECT, SYNTHESIZE, ORGANIZE
        - If a starter is tied to one of the snippets below, include its exact `context_id`;
          otherwise use `context_id` = "general". Context IDs (like "stale_0") are internal —
          NEVER mention one inside the prompt text itself.
        - Only items annotated "(your note)" are the person's own writing — "you wrote" framing
          applies to those and nothing else.
        - Items annotated "(article)", "(video)", "(course lecture)", "(codebase)" are things they
          saved, not things they wrote — say "that article", "the video".
        - Return ONLY valid JSON. No markdown fences, no explanation. Return [] if no snippet
          supports a concrete starter.

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

        // "You saved these four things" is not a reason to start a conversation.
        // With titles alone the model can only paraphrase a title back and ask
        // which part was interesting — and, given a title like
        // "Real Headline ‣ Some Blog", guess wrong about what the piece even
        // said. So recent items only become a candidate for the ones Grove
        // actually knows something about, and the substance goes in the prompt.
        let groundedRecent = Array(
            context.recentItems.prefix(6).filter { grounding(for: $0) != nil }
        )

        if !groundedRecent.isEmpty {
            let lines = groundedRecent
                .prefix(4)
                .compactMap { item in grounding(for: item).map { "  - \(describe(item)) — \($0)" } }
                .joined(separator: "\n")
            candidates.append(StarterLLMContextCandidate(
                id: "recent_items",
                summary: "Recently saved items (last 7 days):\n\(lines)",
                clusterTag: nil,
                itemIDs: groundedRecent.map(\.id),
                boardIDs: StarterContextBuilder.boardIDs(for: groundedRecent)
            ))
        }

        for (index, item) in context.staleItems.prefix(2).enumerated() {
            var summary = "Stale item not touched in 30+ days: \(describe(item))"
            if let text = grounding(for: item) {
                summary += " — \(text)"
            }
            candidates.append(StarterLLMContextCandidate(
                id: "stale_\(index)",
                summary: summary,
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
                let lines = recentTaggedItems
                    .prefix(4)
                    .map { item in
                        let base = "  - \(describe(item))"
                        return grounding(for: item).map { "\(base) — \($0)" } ?? base
                    }
                    .joined(separator: "\n")
                candidates.append(StarterLLMContextCandidate(
                    id: "recent_tag",
                    summary: "Recent cluster for tag \"\(tag)\" (\(context.topRecentTagCount) items):\n\(lines)",
                    clusterTag: nil,
                    itemIDs: recentTaggedItems.map(\.id),
                    boardIDs: StarterContextBuilder.boardIDs(for: recentTaggedItems)
                ))
            }
        }

        if let pair = context.contradictionPairs.first {
            let pairItems = [pair.source, pair.target]
            let titles = pairItems.map { describe($0) }.joined(separator: " vs ")
            var summary = "Two items in tension: \(titles)"
            if let reason = pair.reason {
                summary += " — \(reason)"
            }
            candidates.append(StarterLLMContextCandidate(
                id: "contradiction",
                summary: summary,
                clusterTag: nil,
                itemIDs: pairItems.map(\.id),
                boardIDs: StarterContextBuilder.boardIDs(for: pairItems)
            ))
        }

        if let cluster = context.unboardedCluster, !didShowClusterBubble {
            let titles = cluster.items.prefix(4).map { describe($0) }.joined(separator: ", ")
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

    // MARK: - Item Framing

    /// One item as the model sees it: type annotation plus a title with the
    /// publication suffix removed.
    @MainActor
    private static func describe(_ item: Item) -> String {
        "(\(item.type.llmLabel)) \"\(trimmedTitle(item.title))\""
    }

    /// The most concrete thing Grove knows about an item beyond its title —
    /// the person's own reflection first, then a stored summary, then the
    /// content itself. Nil when the title is all there is.
    @MainActor
    static func grounding(for item: Item) -> String? {
        let reflection = item.reflections
            .sorted { $0.position < $1.position }
            .lazy
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let reflection {
            return "their note on it: \(excerpt(reflection))"
        }

        let summary = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let summary, !summary.isEmpty {
            return excerpt(summary)
        }

        // Short scraps of content are usually boilerplate ("Sign in to
        // continue"), not something to build a question on.
        let content = item.retrievalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.count >= 80 {
            return excerpt(content)
        }

        return nil
    }

    private static func excerpt(_ text: String, limit: Int = 200) -> String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    /// Page titles routinely carry the publication after a separator
    /// ("Real Headline ‣ Some Blog"). Left in, the model reads the publication
    /// as part of the subject matter and invents a topic from it. Only
    /// separators that are unambiguously structural are cut — an em dash can
    /// belong to the headline itself.
    static func trimmedTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" ‣ ", " | ", " » ", " · "] {
            guard let range = title.range(of: separator, options: .backwards) else { continue }
            let head = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(title[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            // A publication name is short and leaves a real headline behind it.
            if head.count >= 12, tail.count <= 40 {
                title = head
            }
        }
        return title
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
            let prompt = sanitizePrompt(payload.prompt, candidateIDs: candidates.map(\.id))
            let label = normalizeLabel(payload.label)
            guard !prompt.isEmpty else { return nil }

            let candidate = payload.contextID.flatMap { candidateLookup[$0] }
            return PromptBubble(
                prompt: prompt,
                label: label,
                clusterTag: candidate?.clusterTag,
                clusterItemIDs: candidate?.itemIDs ?? [],
                boardIDs: candidate?.boardIDs ?? [],
                contextID: candidate?.id
            )
        }

        return parsed.isEmpty ? nil : Array(parsed.prefix(3))
    }

    // MARK: - Output Sanitization

    /// Labels the UI is designed around. The LLM occasionally invents its own
    /// ("CONTRADICTION", "CONFLICT") despite instructions, so unknown labels
    /// are mapped to the closest canonical one.
    private static let allowedLabels: Set<String> = [
        "REVISIT", "EXPLORE", "RESOLVE", "REFLECT", "SYNTHESIZE", "ORGANIZE",
    ]

    private static let labelFallbacks: [String: String] = [
        "CONTRADICTION": "RESOLVE",
        "CONFLICT": "RESOLVE",
        "TENSION": "RESOLVE",
        "CONNECT": "SYNTHESIZE",
        "COMPARE": "SYNTHESIZE",
    ]

    static func normalizeLabel(_ raw: String) -> String {
        let label = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if allowedLabels.contains(label) { return label }
        return labelFallbacks[label] ?? "EXPLORE"
    }

    /// Strips internal context IDs the LLM sometimes leaks into the question
    /// text (e.g. `... AI agents (stale_1) reflect ...`).
    ///
    /// Two rules, because some IDs are also ordinary English. The
    /// parenthesized form is always an ID leak and always goes. A *bare*
    /// occurrence is only removed when the ID could not be a word the user
    /// meant — it has to look machine-made (an underscore or a digit) and
    /// stand on its own word boundaries. Without that guard, IDs like
    /// `contradiction` and `general` were being cut out of perfectly good
    /// questions, leaving "Want to work through the  between X and Y?".
    static func sanitizePrompt(_ raw: String, candidateIDs: [String]) -> String {
        var prompt = raw
        for id in candidateIDs + ["general"] where !id.isEmpty {
            prompt = prompt.replacingOccurrences(of: " (\(id))", with: "")
            prompt = prompt.replacingOccurrences(of: "(\(id))", with: "")

            guard id.contains("_") || id.contains(where: { $0.isNumber }) else { continue }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: id))\\b"
            prompt = prompt.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        while prompt.contains("  ") {
            prompt = prompt.replacingOccurrences(of: "  ", with: " ")
        }
        return prompt.trimmingCharacters(in: .whitespacesAndNewlines)
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
