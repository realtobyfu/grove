import SwiftUI
import SwiftData

/// Messages-like chat UI for iOS Dialectics conversations.
/// Shows message bubbles in a ScrollView with text input at bottom.
struct MobileChatView: View {
    @Bindable var conversation: Conversation
    @Environment(\.modelContext) private var modelContext
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var allItemsForContext: [Item]
    @State private var dialecticsService = DialecticsService()
    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy?
    @State private var paywallPresentation: PaywallPresentation?

    private var seedItems: [Item] {
        allItemsForContext.filter { conversation.seedItemIDs.contains($0.id) }
    }

    private var boardProposal: BoardProposal? {
        dialecticsService.pendingBoardProposal(for: conversation)
    }

    /// The visible reply the pending proposal belongs to, if it is shown.
    private func proposalAnchorID(for proposal: BoardProposal?) -> UUID? {
        guard let messageID = proposal?.messageID,
              conversation.visibleMessages.contains(where: { $0.id == messageID }) else { return nil }
        return messageID
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    let boardProposal = boardProposal
                    let proposalAnchorID = proposalAnchorID(for: boardProposal)
                    LazyVStack(spacing: Spacing.sm) {
                        if conversation.visibleMessages.isEmpty && !dialecticsService.isGenerating {
                            emptyPrompt
                        }

                        ForEach(conversation.visibleMessages) { message in
                            MobileChatBubble(
                                message: message,
                                onSaveAsReflection: message.role == .assistant ? {
                                    saveAsReflection(message)
                                } : nil,
                                onSaveAsNote: message.role == .assistant ? {
                                    saveAsNote(message)
                                } : nil
                            )
                            .id(message.id)

                            // Under the reply that proposed it, once.
                            if let boardProposal, proposalAnchorID == message.id {
                                boardProposalCard(boardProposal)
                            }
                        }

                        // Streaming indicator
                        if dialecticsService.isGenerating {
                            streamingIndicator
                        }

                        if let boardProposal, proposalAnchorID == nil {
                            boardProposalCard(boardProposal)
                        }
                    }
                    .padding(.horizontal, LayoutDimensions.contentPaddingH)
                    .padding(.vertical, Spacing.md)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: boardProposal?.id) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            if !seedItems.isEmpty {
                contextBanner
            }

            Divider()

            // Input area
            inputArea
        }
        .background(Color.bgPrimary)
        .navigationTitle(conversation.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $paywallPresentation) { presentation in
            ProPaywallView(presentation: presentation)
        }
        // A send refused for the free cloud limit, including one started
        // elsewhere (an item's "discuss" opener) for this conversation.
        .onReceive(NotificationCenter.default.publisher(for: .groveDialecticsLimitReached)) { _ in
            guard !dialecticsService.canSendMessage(in: conversation) else { return }
            presentChatLimitPaywall()
        }
    }

    private func presentChatLimitPaywall() {
        guard paywallPresentation == nil else { return }
        paywallPresentation = paywallCoordinator.present(
            feature: .dialectics,
            source: .dialecticsLimit
        )
    }

    private func boardProposalCard(_ proposal: BoardProposal) -> some View {
        BoardProposalCard(
            proposal: proposal,
            onCreate: {
                dialecticsService.confirmBoardProposal(for: conversation, context: modelContext)
            },
            onDecline: {
                dialecticsService.declineBoardProposal(for: conversation, context: modelContext)
            }
        )
        .id(BoardProposalCard.scrollID)
    }

    // MARK: - Empty conversation

    private var emptyPrompt: some View {
        GroveEmptyState(
            title: "What are you thinking through?",
            detail: "Chat can search your library, highlights and reflections as you talk."
        )
    }

    // MARK: - Input area

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            TextField("Message...", text: $inputText, axis: .vertical)
                .font(.groveBody)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1...5)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.bgInput, in: RoundedRectangle(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .stroke(Color.borderInput, lineWidth: 1)
                }
                #if os(iOS)
                .dropDestination(for: URL.self) { urls, _ in
                    handleItemDrop(urls: urls)
                }
                #endif

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.groveBody)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
                    .frame(minWidth: LayoutDimensions.minTouchTarget,
                           minHeight: LayoutDimensions.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.4)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Context banner

    private var contextBanner: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                Text("Context:")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)

                ForEach(seedItems) { item in
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10, weight: .medium))
                        Text(item.title)
                            .lineLimit(1)
                    }
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.bgCard, in: RoundedRectangle(cornerRadius: Radius.tag))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.tag)
                            .stroke(Color.borderPrimary, lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        }
    }

    // MARK: - Streaming indicator

    private var streamingIndicator: some View {
        HStack {
            if !dialecticsService.streamingText.isEmpty {
                Text(dialecticsService.streamingText)
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.card)
                            .stroke(Color.borderPrimary, lineWidth: 1)
                    }
            } else {
                ProgressView()
                    .padding(Spacing.md)
            }
            Spacer(minLength: 60)
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !dialecticsService.isGenerating
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Out of free cloud conversations: keep the draft, show the paywall.
        guard dialecticsService.canSendMessage(in: conversation) else {
            presentChatLimitPaywall()
            return
        }
        inputText = ""

        Task {
            _ = await dialecticsService.sendMessage(
                userText: text,
                conversation: conversation,
                context: modelContext
            )
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        // The card is the last thing shown only while nothing came after its reply.
        let anchorID = proposalAnchorID(for: boardProposal)
        if boardProposal != nil, anchorID == nil || anchorID == conversation.visibleMessages.last?.id {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                proxy.scrollTo(BoardProposalCard.scrollID, anchor: .bottom)
            }
        } else if let lastMessage = conversation.visibleMessages.last {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Drop handling (P11.3)

    private func handleItemDrop(urls: [URL]) -> Bool {
        for url in urls {
            if url.scheme == "grove", url.host == "item" {
                if let uuid = UUID(uuidString: url.lastPathComponent) {
                    let allItems: [Item] = modelContext.fetchAll()
                    if let item = allItems.first(where: { $0.id == uuid }) {
                        inputText = "Let's discuss \"\(item.title)\"."
                        if !conversation.seedItemIDs.contains(item.id) {
                            conversation.seedItemIDs.append(item.id)
                        }
                        return true
                    }
                }
            } else {
                // Regular URL — find item by sourceURL
                let urlString = url.absoluteString
                let allItems: [Item] = modelContext.fetchAll()
                if let item = allItems.first(where: { $0.sourceURL == urlString }) {
                    inputText = "Let's discuss \"\(item.title)\"."
                    if !conversation.seedItemIDs.contains(item.id) {
                        conversation.seedItemIDs.append(item.id)
                    }
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Message actions (P6.7)

    private func saveAsReflection(_ message: ChatMessage) {
        // Save to the first seed item if available
        let seedItem = conversation.seedItemIDs.first.flatMap { seedID in
            let allItems: [Item] = modelContext.fetchAll()
            return allItems.first { $0.id == seedID }
        }
        if let item = seedItem {
            _ = dialecticsService.saveAsReflection(
                content: message.content,
                itemTitle: item.title,
                blockType: .keyInsight,
                conversation: conversation,
                context: modelContext
            )
        }
    }

    private func saveAsNote(_ message: ChatMessage) {
        let title = String(message.content.prefix(60))
        _ = dialecticsService.saveAsNote(
            content: message.content,
            title: title,
            conversation: conversation,
            context: modelContext
        )
    }
}
