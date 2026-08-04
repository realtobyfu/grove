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
    You are a thinking partner embedded in Grove, a personal knowledge app. The user saves articles, notes, \
    videos, and lectures, then writes reflections on them. Your role is substantive intellectual dialogue — \
    not summarizing, not interviewing.

    Core rules:
    - Contribute before you ask. Every reply must offer something of your own — a specific observation, a tension you noticed, a claim worth testing — grounded in the user's actual items. Only then may you ask.
    - At most ONE question per reply. Never stack questions.
    - Ground every reply in specifics: quote or paraphrase actual claims from the user's items, and reference items with [[Item Title]] wiki-link syntax. If you need material, look it up with a tool rather than asking the user to supply it.
    - If the user is uncertain, brief, or says they don't know: do not ask another question. Offer your own provisional reading of the material and invite them to push back.
    - When the user's items or reflections genuinely conflict, name the conflict directly: "You wrote X, but [[Other Item]] argues Y." Work toward a position that accounts for both — or say plainly why they cannot be reconciled.
    - Never be sycophantic. Disagree when the material supports it.
    - Plain language. No philosophical name-dropping, no "deeper divide" framing, no seminar voice.
    - Keep replies to 1-3 short paragraphs. Use markdown; **bold** sparingly.
    - After 3-4 exchanges, offer to save key insights as reflection blocks.
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

        // Run agentic loop — native tool calling when the provider supports it,
        // prompt-based JSON tool calls otherwise.
        let tools = KnowledgeBaseTools(modelContext: context)
        var currentTurns = turns
        var assistantContent: String?

        if await provider.supportsNativeTools {
            assistantContent = await runNativeToolLoop(
                turns: &currentTurns,
                tools: tools,
                conversation: conversation,
                context: context
            )
        } else {
            assistantContent = await runPromptToolLoop(
                turns: &currentTurns,
                tools: tools,
                conversation: conversation,
                context: context
            )
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

    // MARK: - Native Tool Loop

    private static let maxNativeToolRounds = 5
    private static let nativeToolNote = "Use the provided tools to search or modify the knowledge base when needed."

    private func runNativeToolLoop(
        turns: inout [ChatTurn],
        tools: KnowledgeBaseTools,
        conversation: Conversation,
        context: ModelContext
    ) async -> String? {
        // The persisted system prompt carries prompt-based tool instructions;
        // swap them for a short note so the model uses native tools instead.
        turns = turns.map { turn in
            guard turn.role == "system", turn.content.contains(KnowledgeBaseTools.toolDescriptions) else {
                return turn
            }
            return ChatTurn(
                role: "system",
                content: turn.content.replacingOccurrences(
                    of: KnowledgeBaseTools.toolDescriptions,
                    with: Self.nativeToolNote
                )
            )
        }

        for _ in 0..<Self.maxNativeToolRounds {
            guard let response = await provider.completeChat(
                messages: turns,
                tools: KnowledgeBaseTools.toolSpecs,
                service: "dialectics"
            ) else {
                lastError = await provider.lastError?.userMessage
                return nil
            }

            guard !response.toolCalls.isEmpty else {
                let content = response.content?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (content?.isEmpty == false) ? content : nil
            }

            turns.append(ChatTurn(
                role: "assistant",
                content: response.content ?? "",
                toolCalls: response.toolCalls
            ))

            for call in response.toolCalls {
                // Persist the call and its result as hidden messages for traceability
                let toolCallMsg = ChatMessage(
                    role: .assistant,
                    content: "\(call.name)(\(call.argumentsJSON))",
                    position: conversation.nextPosition,
                    isHidden: true,
                    toolCallName: call.name
                )
                toolCallMsg.conversation = conversation
                conversation.messages.append(toolCallMsg)
                context.insert(toolCallMsg)

                let toolResult = await tools.fulfill(toolName: call.name, args: call.stringArguments)
                    ?? "Tool \"\(call.name)\" returned no results."

                let toolResultMsg = ChatMessage(
                    role: .tool,
                    content: toolResult,
                    position: conversation.nextPosition,
                    isHidden: true,
                    toolCallName: call.name
                )
                toolResultMsg.conversation = conversation
                conversation.messages.append(toolResultMsg)
                context.insert(toolResultMsg)

                turns.append(ChatTurn(role: "tool", content: toolResult, toolCallID: call.id))
            }
        }

        // Round limit reached — request a final answer without tools
        let result = await provider.completeChat(messages: turns, service: "dialectics")
        if let content = result?.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            return content
        }
        lastError = await provider.lastError?.userMessage
        return nil
    }

    // MARK: - Prompt-Based Tool Loop (providers without native tool calling)

    private func runPromptToolLoop(
        turns currentTurns: inout [ChatTurn],
        tools: KnowledgeBaseTools,
        conversation: Conversation,
        context: ModelContext
    ) async -> String? {
        var assistantContent: String?

        for _ in 0..<Self.maxToolRounds {
            guard let result = await provider.completeChat(messages: currentTurns, service: "dialectics") else {
                lastError = await provider.lastError?.userMessage
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
            if let content = fallbackResult?.content.trimmingCharacters(in: .whitespacesAndNewlines) {
                // Check if fallback also returned a tool call — execute it one more time
                if let toolCall = parseToolCall(from: content) {
                    let toolResult = await tools.fulfill(toolName: toolCall.name, args: toolCall.args)
                        ?? "Tool \"\(toolCall.name)\" returned no results."
                    currentTurns.append(ChatTurn(role: "assistant", content: content))
                    currentTurns.append(ChatTurn(role: "user", content: "[Tool result for \(toolCall.name)]:\n\(toolResult)\n\nNow please respond to the user in natural language. Do not output a tool_call."))
                    let finalResult = await provider.completeChat(messages: currentTurns, service: "dialectics")
                    assistantContent = finalResult?.content.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    assistantContent = content
                }
            }
            if assistantContent == nil {
                lastError = await provider.lastError?.userMessage
            }
        }

        // Safety net: if the final content still looks like a raw tool call, ask once more without tools
        if let content = assistantContent, looksLikeToolCall(content) {
            currentTurns.append(ChatTurn(role: "assistant", content: content))
            currentTurns.append(ChatTurn(role: "user", content: "Please respond in natural language. Do not output a tool_call JSON."))
            let retryResult = await provider.completeChat(messages: currentTurns, service: "dialectics")
            if let retryContent = retryResult?.content.trimmingCharacters(in: .whitespacesAndNewlines),
               !looksLikeToolCall(retryContent) {
                assistantContent = retryContent
            }
        }

        return assistantContent
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
            parts.append(LLMContextBuilder.itemDescription(item, contentLimit: 500))
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Tool Call Parsing

    private struct ToolCall {
        let name: String
        let args: [String: String]
    }

    private func parseToolCall(from content: String) -> ToolCall? {
        // Strip markdown fences if present
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: .newlines)
            cleaned = lines
                .drop(while: { $0.hasPrefix("```") })
                .reversed().drop(while: { $0.hasPrefix("```") }).reversed()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try parsing the whole string as JSON first
        if let result = parseToolCallJSON(cleaned) { return result }

        // Fallback: extract the first {...} JSON object from the content
        guard let openBrace = cleaned.firstIndex(of: "{"),
              let closeBrace = cleaned.lastIndex(of: "}") else {
            return nil
        }
        let jsonStr = String(cleaned[openBrace...closeBrace])
        return parseToolCallJSON(jsonStr)
    }

    private func parseToolCallJSON(_ jsonStr: String) -> ToolCall? {
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

    /// Returns true if the content looks like a raw tool call JSON that shouldn't be shown to the user.
    private func looksLikeToolCall(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("\"tool_call\"") && trimmed.contains("\"name\"")
    }

    // MARK: - Wiki-Link Extraction

    private func extractReferencedItemIDs(from content: String, context: ModelContext) -> [UUID] {
        let pattern = /\[\[([^\]]+)\]\]/
        let matches = content.matches(of: pattern)
        guard !matches.isEmpty else { return [] }

        let allItems: [Item] = context.fetchAll()
        let titles = matches.map { String($0.1) }

        return titles.compactMap { title in
            ItemResolver.resolve(title, in: allItems)?.id
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
        let allItems: [Item] = context.fetchAll()
        guard let item = ItemResolver.resolve(itemTitle, in: allItems) else {
            return nil
        }

        let position = (item.reflections.map(\.position).max() ?? -1) + 1
        let block = ReflectionBlock(item: item, blockType: blockType, content: content, position: position)
        block.conversation = conversation
        context.insert(block)
        item.reflections.append(block)
        conversation.createdReflections.append(block)
        try? context.save()
        WikiLinkSync.sync(item: item, content: content, modelContext: context)
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
            let allItems: [Item] = context.fetchAll()
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
        let allItems: [Item] = context.fetchAll()
        guard let source = ItemResolver.resolve(sourceTitle, in: allItems),
              let target = ItemResolver.resolve(targetTitle, in: allItems) else {
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
