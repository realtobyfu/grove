import Foundation
import SwiftData

/// Protocol for testability.
@MainActor
protocol DialecticsServiceProtocol {
    func startConversation(
        trigger: ConversationTrigger,
        seedItems: [Item],
        board: Board?,
        context: ModelContext
    ) -> Conversation

    func sendMessage(
        userText: String,
        conversation: Conversation,
        context: ModelContext
    ) async -> ChatMessage?
}

/// Orchestrates dialectical conversations with the LLM.
/// Handles conversation lifecycle, agentic tool-call loop, and context management.
@MainActor
@Observable
final class DialecticsService: DialecticsServiceProtocol {
    private let provider: LLMProvider
    var isGenerating = false
    var streamingText = ""
    var lastError: String?

    private static let maxToolRounds = 3
    private static let contextSummaryThreshold = 20
    private static let keepRecentMessages = 10

    init(provider: LLMProvider = LLMServiceConfig.makeProvider()) {
        self.provider = provider
    }

    // MARK: - System Prompt

    private static let systemPrompt = """
    You are a dialectical thinking partner embedded in a personal knowledge management app called Grove. \
    The user saves articles, notes, videos, and lectures, then writes reflections on them. Your role is to \
    engage in substantive intellectual dialogue — not to summarize or be agreeable.

    You have three dialectical modes. Choose the appropriate mode based on context — do not announce which mode you are using:

    1. SOCRATIC MODE — Use when probing assumptions or when the user holds a position they haven't fully examined.
       - Ask one probing question at a time. "What do you mean by X?" "What evidence supports that?"
       - Surface hidden premises. Expose what the user takes for granted.
       - Do not offer your own conclusions until the user's reasoning is fully drawn out.

    2. HEGELIAN MODE — Use when contradictions exist between items or reflections in the knowledge base, or when the user holds two conflicting views.
       - Name the thesis and antithesis directly. "You've written that X, but also that Y — these are in tension."
       - Drive toward synthesis: a third position that preserves the truth in both sides.
       - Use [[Item Title]] wiki-link syntax to reference conflicting items explicitly.

    3. NIETZSCHEAN MODE — Use when the user has collected multiple perspectives without committing, or when a topic invites perspectivism.
       - Illuminate how each perspective reflects a particular vantage point, interest, or power relation.
       - Resist the urge to synthesize prematurely. Multiple irreconcilable views can coexist.
       - Challenge the user to identify which perspective serves their thinking best — and why.

    Context signals for mode selection:
    - Items with .contradicts connections → prefer Hegelian
    - A single item or position being explored → prefer Socratic
    - Many items on a topic with no clear throughline → prefer Nietzschean
    - Mixed signals: default to Socratic, shift as the conversation reveals structure

    Additional rules:
    - Never be sycophantic. Engage substantively with ideas.
    - Keep responses focused and concise (2-4 paragraphs max).
    - When you notice a tension between two items or reflections, name it directly.
    - If the user's position seems underdeveloped, push for deeper reasoning.
    - After 3-4 exchanges, offer to save key insights as reflection blocks.
    - Use [[Item Title]] wiki-link syntax when referencing items from the knowledge base.
    - Use markdown formatting: **bold** for emphasis, bullet points for lists.
    - When you want to look up something in the user's knowledge base, output a tool_call JSON.

    \(KnowledgeBaseTools.toolDescriptions)
    """

    // MARK: - Conversation Lifecycle

    func startConversation(
        trigger: ConversationTrigger,
        seedItems: [Item],
        board: Board?,
        context: ModelContext
    ) -> Conversation {
        let conversation = Conversation(
            trigger: trigger,
            board: board,
            seedItemIDs: seedItems.map(\.id)
        )
        context.insert(conversation)

        // System message (hidden)
        let systemMsg = ChatMessage(
            role: .system,
            content: Self.systemPrompt,
            position: 0,
            isHidden: true
        )
        systemMsg.conversation = conversation
        conversation.messages.append(systemMsg)
        context.insert(systemMsg)

        // Inject seed item context if present
        if !seedItems.isEmpty {
            let contextText = buildSeedContext(items: seedItems)
            let contextMsg = ChatMessage(
                role: .system,
                content: contextText,
                position: 1,
                isHidden: true
            )
            contextMsg.conversation = conversation
            conversation.messages.append(contextMsg)
            context.insert(contextMsg)
        }

        try? context.save()
        return conversation
    }

    func sendMessage(
        userText: String,
        conversation: Conversation,
        context: ModelContext
    ) async -> ChatMessage? {
        guard !isGenerating else { return nil }
        isGenerating = true
        streamingText = ""
        lastError = nil

        // Save user message
        let userMsg = ChatMessage(
            role: .user,
            content: userText,
            position: conversation.nextPosition
        )
        userMsg.conversation = conversation
        conversation.messages.append(userMsg)
        context.insert(userMsg)
        conversation.updatedAt = .now
        try? context.save()

        // Build message history for LLM
        let turns = buildTurns(for: conversation, context: context)

        // Run agentic loop
        let tools = KnowledgeBaseTools(modelContext: context)
        var currentTurns = turns
        var assistantContent: String?

        for _ in 0..<Self.maxToolRounds {
            guard let result = await provider.completeChat(messages: currentTurns, service: "dialectics") else {
                if let groqProvider = provider as? GroqProvider {
                    lastError = groqProvider.lastError?.userMessage
                }
                break
            }

            let content = result.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if response contains a tool call
            if let toolCall = parseToolCall(from: content) {
                // Save tool call message (hidden)
                let toolCallMsg = ChatMessage(
                    role: .assistant,
                    content: content,
                    position: conversation.nextPosition,
                    isHidden: true,
                    toolCallName: toolCall.name
                )
                toolCallMsg.conversation = conversation
                conversation.messages.append(toolCallMsg)
                context.insert(toolCallMsg)

                // Fulfill tool call
                let toolResult = await tools.fulfill(toolName: toolCall.name, args: toolCall.args)
                    ?? "Tool \"\(toolCall.name)\" returned no results."

                // Save tool result (hidden)
                let toolResultMsg = ChatMessage(
                    role: .tool,
                    content: toolResult,
                    position: conversation.nextPosition,
                    isHidden: true,
                    toolCallName: toolCall.name
                )
                toolResultMsg.conversation = conversation
                conversation.messages.append(toolResultMsg)
                context.insert(toolResultMsg)

                // Append to turns and loop
                currentTurns.append(ChatTurn(role: "assistant", content: content))
                currentTurns.append(ChatTurn(role: "user", content: "[Tool result for \(toolCall.name)]:\n\(toolResult)"))
                continue
            }

            // No tool call — this is the final response
            assistantContent = content
            break
        }

        // If no response from loop, try one last direct call
        if assistantContent == nil && lastError == nil {
            let fallbackResult = await provider.completeChat(messages: currentTurns, service: "dialectics")
            assistantContent = fallbackResult?.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if assistantContent == nil, let groqProvider = provider as? GroqProvider {
                lastError = groqProvider.lastError?.userMessage
            }
        }

        guard let finalContent = assistantContent, !finalContent.isEmpty else {
            if lastError == nil {
                lastError = "Unable to generate a response. Try again."
            }
            isGenerating = false
            return nil
        }

        // Extract referenced item titles from [[wiki-links]]
        let referencedIDs = extractReferencedItemIDs(from: finalContent, context: context)

        // Save assistant response
        let assistantMsg = ChatMessage(
            role: .assistant,
            content: finalContent,
            position: conversation.nextPosition,
            referencedItemIDs: referencedIDs
        )
        assistantMsg.conversation = conversation
        conversation.messages.append(assistantMsg)
        context.insert(assistantMsg)
        conversation.updatedAt = .now
        try? context.save()

        // Auto-title after first exchange
        if conversation.title == "New Conversation" && conversation.visibleMessages.count >= 3 {
            Task {
                await generateTitle(for: conversation, context: context)
            }
        }

        isGenerating = false
        return assistantMsg
    }

    // MARK: - Title Generation

    func generateTitle(for conversation: Conversation, context: ModelContext) async {
        let visibleMsgs = conversation.visibleMessages.prefix(6)
        let transcript = visibleMsgs.map { "\($0.role.rawValue): \($0.content.prefix(200))" }.joined(separator: "\n")

        let result = await provider.complete(
            system: "Generate a short title (3-6 words) for this conversation. Output only the title, nothing else.",
            user: transcript,
            service: "dialectics"
        )

        if let title = result?.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty, title.count < 60 {
            conversation.title = title.replacingOccurrences(of: "\"", with: "")
            try? context.save()
        }
    }

    // MARK: - Context Building

    private func buildTurns(for conversation: Conversation, context: ModelContext) -> [ChatTurn] {
        var messages = conversation.sortedMessages

        // Context window management: summarize if too long
        if messages.count > Self.contextSummaryThreshold {
            messages = summarizeOldMessages(messages, context: context, conversation: conversation)
        }

        return messages.map { msg in
            // Map tool results to user role for API compatibility
            let role: String
            switch msg.role {
            case .system: role = "system"
            case .assistant: role = "assistant"
            case .user: role = "user"
            case .tool: role = "user"
            }
            return ChatTurn(role: role, content: msg.content)
        }
    }

    private func summarizeOldMessages(_ messages: [ChatMessage], context: ModelContext, conversation: Conversation) -> [ChatMessage] {
        let keepCount = Self.keepRecentMessages
        let systemMessages = messages.filter { $0.role == .system }
        let nonSystem = messages.filter { $0.role != .system }

        guard nonSystem.count > keepCount else { return messages }

        let oldMessages = nonSystem.dropLast(keepCount)
        let recentMessages = Array(nonSystem.suffix(keepCount))

        // Build summary of old messages
        let summaryText = oldMessages.filter { !$0.isHidden }.map { msg in
            "\(msg.role.rawValue): \(String(msg.content.prefix(150)))"
        }.joined(separator: "\n")

        let summaryMsg = ChatMessage(
            role: .system,
            content: "[Summary of earlier conversation]\n\(summaryText)",
            position: -1,
            isHidden: true
        )

        return systemMessages + [summaryMsg] + recentMessages
    }

    private func buildSeedContext(items: [Item]) -> String {
        var parts = ["[Context: The user wants to discuss the following items from their knowledge base]\n"]
        for item in items {
            var desc = "## \(item.title)\nType: \(item.type.rawValue)"
            let tags = item.tags.map(\.name).joined(separator: ", ")
            if !tags.isEmpty { desc += "\nTags: \(tags)" }
            if let content = item.content {
                desc += "\nContent: \(String(content.prefix(500)))"
            }
            if !item.reflections.isEmpty {
                desc += "\nUser reflections:"
                for block in item.reflections.sorted(by: { $0.position < $1.position }).prefix(3) {
                    desc += "\n- [\(block.blockType.displayName)] \(String(block.content.prefix(200)))"
                }
            }
            parts.append(desc)
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Tool Call Parsing

    private struct ToolCall {
        let name: String
        let args: [String: String]
    }

    private func parseToolCall(from content: String) -> ToolCall? {
        // Look for {"tool_call": {...}} pattern
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown fences if present
        var jsonStr = trimmed
        if jsonStr.hasPrefix("```") {
            let lines = jsonStr.components(separatedBy: .newlines)
            let inner = lines.dropFirst().dropLast()
            jsonStr = inner.joined(separator: "\n")
        }

        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let toolCall = json["tool_call"] as? [String: Any],
              let name = toolCall["name"] as? String else {
            return nil
        }

        var args: [String: String] = [:]
        if let argsDict = toolCall["args"] as? [String: Any] {
            for (key, value) in argsDict {
                args[key] = "\(value)"
            }
        }

        return ToolCall(name: name, args: args)
    }

    // MARK: - Wiki-Link Extraction

    private func extractReferencedItemIDs(from content: String, context: ModelContext) -> [UUID] {
        let pattern = /\[\[([^\]]+)\]\]/
        let matches = content.matches(of: pattern)
        guard !matches.isEmpty else { return [] }

        let allItems = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let titles = matches.map { String($0.1) }

        return titles.compactMap { title in
            allItems.first(where: { $0.title.lowercased() == title.lowercased() })?.id
        }
    }

    // MARK: - Item-Anchored Conversation

    /// Creates a conversation anchored to a single item and generates an opening assistant message.
    func startDiscussion(item: Item, context: ModelContext) async -> Conversation {
        let conversation = startConversation(
            trigger: .userInitiated,
            seedItems: [item],
            board: item.boards.first,
            context: context
        )
        // Title the conversation immediately so it's identifiable
        conversation.title = "Discuss: \(item.title)"
        try? context.save()

        // Generate opening message from assistant
        let openingPrompt = """
        You are starting a focused discussion about this item from the user's knowledge base.
        Generate a single engaging opening message (2-3 sentences) that:
        1. Acknowledges the item by name
        2. Identifies the most interesting or debatable aspect you notice
        3. Ends with a specific question to invite the user into dialogue
        Do NOT use bullet points. Write naturally and directly.
        """

        let itemContext = buildSeedContext(items: [item])
        let result = await provider.complete(
            system: openingPrompt,
            user: itemContext,
            service: "dialectics"
        )

        let openingContent = result?.content.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Let's explore your note on \"\(item.title)\". What aspect interests you most, or what made you save this?"

        // Extract any wiki-link references from the opening
        let referencedIDs = extractReferencedItemIDs(from: openingContent, context: context)

        let assistantMsg = ChatMessage(
            role: .assistant,
            content: openingContent,
            position: conversation.nextPosition,
            referencedItemIDs: referencedIDs
        )
        assistantMsg.conversation = conversation
        conversation.messages.append(assistantMsg)
        context.insert(assistantMsg)
        conversation.updatedAt = .now
        try? context.save()

        return conversation
    }

    // MARK: - Reflection Creation

    func saveAsReflection(
        content: String,
        itemTitle: String,
        blockType: ReflectionBlockType,
        conversation: Conversation,
        context: ModelContext
    ) -> ReflectionBlock? {
        let allItems = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        guard let item = allItems.first(where: { $0.title.lowercased() == itemTitle.lowercased() }) else {
            return nil
        }

        let position = (item.reflections.map(\.position).max() ?? -1) + 1
        let block = ReflectionBlock(item: item, blockType: blockType, content: content, position: position)
        block.conversation = conversation
        context.insert(block)
        item.reflections.append(block)
        conversation.createdReflections.append(block)
        try? context.save()
        return block
    }

    // MARK: - Note Creation

    func saveAsNote(
        content: String,
        title: String,
        conversation: Conversation,
        context: ModelContext
    ) -> Item? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty, !content.isEmpty else { return nil }

        let item = Item(title: trimmedTitle, type: .note)
        item.content = content
        item.status = .active
        context.insert(item)

        // Auto-tag the new item asynchronously
        Task {
            let autoTagService = AutoTagService()
            await autoTagService.tagItem(item, in: context)
        }

        // If conversation is item-anchored, create a connection from source item to new note
        if let sourceID = conversation.seedItemIDs.first {
            let allItems = (try? context.fetch(FetchDescriptor<Item>())) ?? []
            if let sourceItem = allItems.first(where: { $0.id == sourceID }), sourceItem.id != item.id {
                let connection = Connection(sourceItem: sourceItem, targetItem: item, type: .related)
                connection.note = "Created from dialectical conversation"
                connection.isAutoGenerated = true
                context.insert(connection)
                sourceItem.outgoingConnections.append(connection)
                item.incomingConnections.append(connection)
            }
        }

        try? context.save()
        return item
    }

    // MARK: - Connection Creation

    func createConnection(
        sourceTitle: String,
        targetTitle: String,
        type: ConnectionType,
        context: ModelContext
    ) -> Connection? {
        let allItems = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        guard let source = allItems.first(where: { $0.title.lowercased() == sourceTitle.lowercased() }),
              let target = allItems.first(where: { $0.title.lowercased() == targetTitle.lowercased() }) else {
            return nil
        }

        let connection = Connection(sourceItem: source, targetItem: target, type: type)
        connection.note = "Created from dialectical conversation"
        connection.isAutoGenerated = true
        context.insert(connection)
        source.outgoingConnections.append(connection)
        target.incomingConnections.append(connection)
        try? context.save()
        return connection
    }
}
