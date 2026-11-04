import Foundation
import SQLiteData

/// Protocol for testability.
@MainActor
protocol DialecticsServiceProtocol {
    func startConversation(
        trigger: ConversationTrigger,
        seedItems: [ItemGraph],
        board: Board?
    ) -> ConversationGraph

    func sendMessage(
        userText: String,
        conversationID: Conversation.ID
    ) async -> ChatMessage?
}

/// Orchestrates dialectical conversations with the LLM.
/// Handles conversation lifecycle, agentic tool-call loop, and context management.
@MainActor
@Observable
final class DialecticsService: DialecticsServiceProtocol {
    private let database: any DatabaseWriter
    private let provider: LLMProvider
    var isGenerating = false
    var streamingText = ""
    var lastError: String?
    /// Called after each write to a conversation, with its ID. A conversation is
    /// a value, so this is how whoever holds one hears that it went out of date
    /// while a reply is still in flight.
    @ObservationIgnored var onConversationChanged: (@MainActor (Conversation.ID) -> Void)?

    private static let maxToolRounds = 3
    private static let contextSummaryThreshold = 20
    private static let keepRecentMessages = 10

    init(
        database: any DatabaseWriter = AppDatabase.current,
        provider: LLMProvider = LLMServiceConfig.makeProvider()
    ) {
        self.database = database
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
        seedItems: [ItemGraph],
        board: Board?
    ) -> ConversationGraph {
        let conversation = Conversation(
            trigger: trigger,
            boardID: board?.id,
            seedItemIDs: seedItems.map(\.id)
        )

        // System message (hidden)
        var messages = [
            ChatMessage(
                role: .system,
                content: Self.systemPrompt,
                position: 0,
                conversationID: conversation.id,
                isHidden: true
            )
        ]

        // Inject seed item context if present
        if !seedItems.isEmpty {
            let contextText = buildSeedContext(items: seedItems)
            messages.append(ChatMessage(
                role: .system,
                content: contextText,
                position: 1,
                conversationID: conversation.id,
                isHidden: true
            ))
        }

        let openingMessages = messages
        database.attempt { db in
            try Conversation.insert { conversation }.execute(db)
            for message in openingMessages {
                try ChatMessage.insert { message }.execute(db)
            }
        }
        return ConversationGraph(conversation: conversation, board: board, messages: openingMessages)
    }

    func sendMessage(
        userText: String,
        conversationID: Conversation.ID
    ) async -> ChatMessage? {
        guard !isGenerating else { return nil }
        isGenerating = true
        streamingText = ""
        lastError = nil

        // Save user message, and build message history for LLM from what's saved.
        // A message that didn't save can't be answered: it wouldn't be in the history.
        guard appendMessage(role: .user, content: userText, to: conversationID) != nil,
              let conversation = fetchConversation(conversationID) else {
            lastError = "Unable to generate a response. Try again."
            isGenerating = false
            return nil
        }
        let turns = buildTurns(for: conversation)

        // Run agentic loop — native tool calling when the provider supports it,
        // prompt-based JSON tool calls otherwise.
        let tools = KnowledgeBaseTools(database: database)
        var currentTurns = turns
        var assistantContent: String?

        if await provider.supportsNativeTools {
            assistantContent = await runNativeToolLoop(
                turns: &currentTurns,
                tools: tools,
                conversationID: conversationID
            )
        } else {
            assistantContent = await runPromptToolLoop(
                turns: &currentTurns,
                tools: tools,
                conversationID: conversationID
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
        let referencedIDs = extractReferencedItemIDs(from: finalContent)

        // Save assistant response
        let assistantMsg = appendMessage(
            role: .assistant,
            content: finalContent,
            to: conversationID,
            referencedItemIDs: referencedIDs
        )

        // A conversation deleted during the reply leaves nothing to report to.
        if let conversation = fetchConversation(conversationID) {
            if assistantMsg == nil {
                lastError = "Unable to generate a response. Try again."
            }

            // Auto-title after first exchange
            if conversation.title == "New Conversation" && conversation.visibleMessages.count >= 3 {
                Task {
                    await generateTitle(for: conversationID)
                }
            }
        }

        isGenerating = false
        return assistantMsg
    }

    /// Adds a message to the end of a conversation. Returns it, or `nil` when the
    /// conversation is gone, which happens if it's deleted while a reply is in
    /// flight.
    ///
    /// The position is read inside the transaction. A `ConversationGraph` held
    /// across an `await` knows nothing of messages written since, so its
    /// `nextPosition` would hand out a duplicate.
    @discardableResult
    func appendMessage(
        role: ChatRole,
        content: String,
        to conversationID: Conversation.ID,
        isHidden: Bool = false,
        toolCallName: String? = nil,
        referencedItemIDs: [UUID] = []
    ) -> ChatMessage? {
        let saved = database.attempt { db -> ChatMessage? in
            guard try Conversation.modify(conversationID, in: db, { $0.updatedAt = .now }) != nil else {
                return nil
            }
            let last = try ChatMessage
                .where { $0.conversationID.eq(conversationID) }
                .order { $0.position.desc() }
                .fetchOne(db)
            let message = ChatMessage(
                role: role,
                content: content,
                position: (last?.position ?? -1) + 1,
                conversationID: conversationID,
                isHidden: isHidden,
                toolCallName: toolCallName,
                referencedItemIDs: referencedItemIDs
            )
            try ChatMessage.insert { message }.execute(db)
            return message
        } ?? nil
        onConversationChanged?(conversationID)
        return saved
    }

    private func fetchConversation(_ id: Conversation.ID) -> ConversationGraph? {
        database.attemptRead { try ConversationGraph.fetch(id, in: $0) } ?? nil
    }

    // MARK: - Native Tool Loop

    private static let maxNativeToolRounds = 5
    private static let nativeToolNote = "Use the provided tools to search or modify the knowledge base when needed."

    private func runNativeToolLoop(
        turns: inout [ChatTurn],
        tools: KnowledgeBaseTools,
        conversationID: Conversation.ID
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
                appendMessage(
                    role: .assistant,
                    content: "\(call.name)(\(call.argumentsJSON))",
                    to: conversationID,
                    isHidden: true,
                    toolCallName: call.name
                )

                let toolResult = await tools.fulfill(toolName: call.name, args: call.stringArguments)
                    ?? "Tool \"\(call.name)\" returned no results."

                appendMessage(
                    role: .tool,
                    content: toolResult,
                    to: conversationID,
                    isHidden: true,
                    toolCallName: call.name
                )

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
        conversationID: Conversation.ID
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
                appendMessage(
                    role: .assistant,
                    content: content,
                    to: conversationID,
                    isHidden: true,
                    toolCallName: toolCall.name
                )

                // Fulfill tool call
                let toolResult = await tools.fulfill(toolName: toolCall.name, args: toolCall.args)
                    ?? "Tool \"\(toolCall.name)\" returned no results."

                // Save tool result (hidden)
                appendMessage(
                    role: .tool,
                    content: toolResult,
                    to: conversationID,
                    isHidden: true,
                    toolCallName: toolCall.name
                )

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

    func generateTitle(for conversationID: Conversation.ID) async {
        guard let conversation = fetchConversation(conversationID) else { return }
        let visibleMsgs = conversation.visibleMessages.prefix(6)
        let transcript = visibleMsgs.map { "\($0.role.rawValue): \($0.content.prefix(200))" }.joined(separator: "\n")

        let result = await provider.complete(
            system: "Generate a short title (3-6 words) for this conversation. Output only the title, nothing else.",
            user: transcript,
            service: "dialectics"
        )

        if let title = result?.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty, title.count < 60 {
            database.attempt { db in
                try Conversation.modify(conversationID, in: db) {
                    $0.title = title.replacingOccurrences(of: "\"", with: "")
                }
            }
            onConversationChanged?(conversationID)
        }
    }

    // MARK: - Context Building

    private func buildTurns(for conversation: ConversationGraph) -> [ChatTurn] {
        var messages = conversation.sortedMessages

        // Context window management: summarize if too long
        if messages.count > Self.contextSummaryThreshold {
            messages = summarizeOldMessages(messages)
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

    private func summarizeOldMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
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

    private func buildSeedContext(items: [ItemGraph]) -> String {
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

    private func extractReferencedItemIDs(from content: String) -> [UUID] {
        let pattern = /\[\[([^\]]+)\]\]/
        let matches = content.matches(of: pattern)
        guard !matches.isEmpty else { return [] }

        let allItems = fetchAllItems()
        let titles = matches.map { String($0.1) }

        return titles.compactMap { title in
            ItemResolver.resolve(title, in: allItems)?.id
        }
    }

    private func fetchAllItems() -> [Item] {
        database.attemptRead { try Item.all.fetchAll($0) } ?? []
    }

    // MARK: - Item-Anchored Conversation

    /// Creates a conversation anchored to a single item and generates an opening assistant message.
    func startDiscussion(item: ItemGraph) async -> ConversationGraph {
        let conversation = startConversation(
            trigger: .userInitiated,
            seedItems: [item],
            board: item.board
        )
        // Title the conversation immediately so it's identifiable
        database.attempt { db in
            try Conversation.modify(conversation.id, in: db) { $0.title = "Discuss: \(item.title)" }
        }

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
        let referencedIDs = extractReferencedItemIDs(from: openingContent)

        appendMessage(
            role: .assistant,
            content: openingContent,
            to: conversation.id,
            referencedItemIDs: referencedIDs
        )

        return fetchConversation(conversation.id) ?? conversation
    }

    // MARK: - Reflection Creation

    func saveAsReflection(
        content: String,
        itemTitle: String,
        blockType: ReflectionBlockType,
        conversationID: Conversation.ID
    ) -> ReflectionBlock? {
        guard let item = ItemResolver.resolve(itemTitle, in: fetchAllItems()) else {
            return nil
        }

        let saved = database.attempt { db -> ReflectionBlock in
            var block = ReflectionBlock(
                itemID: item.id,
                blockType: blockType,
                content: content,
                position: try ReflectionBlock.nextPosition(onItem: item.id, in: db)
            )
            block.conversationID = conversationID
            let row = block
            try ReflectionBlock.insert { row }.execute(db)
            return row
        }
        guard let saved else { return nil }
        WikiLinkSync.sync(item.id, content: content, database: database)
        onConversationChanged?(conversationID)
        return saved
    }

    // MARK: - Note Creation

    func saveAsNote(
        content: String,
        title: String,
        conversationID: Conversation.ID
    ) -> Item? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty, !content.isEmpty else { return nil }

        var note = Item(title: trimmedTitle, type: .note)
        note.content = content
        note.status = .active
        let item = note

        let saved: Void? = database.attempt { db in
            try Item.insert { item }.execute(db)

            // If conversation is item-anchored, create a connection from source item to new note
            if let sourceID = try Conversation.find(conversationID).fetchOne(db)?.seedItemIDs.first,
               try Item.find(sourceID).fetchOne(db) != nil {
                var connection = Connection(sourceItemID: sourceID, targetItemID: item.id, type: .related)
                connection.note = "Created from dialectical conversation"
                connection.isAutoGenerated = true
                let row = connection
                try Connection.insert { row }.execute(db)
            }
        }
        guard saved != nil else { return nil }

        // Auto-tag the new item asynchronously
        Task {
            let autoTagService = AutoTagService(database: database)
            await autoTagService.tagItem(item.id)
        }

        return item
    }

    // MARK: - Connection Creation

    func createConnection(
        sourceTitle: String,
        targetTitle: String,
        type: ConnectionType
    ) -> Connection? {
        let allItems = fetchAllItems()
        guard let source = ItemResolver.resolve(sourceTitle, in: allItems),
              let target = ItemResolver.resolve(targetTitle, in: allItems) else {
            return nil
        }

        var connection = Connection(sourceItemID: source.id, targetItemID: target.id, type: type)
        connection.note = "Created from dialectical conversation"
        connection.isAutoGenerated = true
        let row = connection
        let saved: Void? = database.attempt { db in
            try Connection.insert { row }.execute(db)
        }
        return saved == nil ? nil : row
    }
}
