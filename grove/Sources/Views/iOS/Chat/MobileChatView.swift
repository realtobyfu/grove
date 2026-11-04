import SQLiteData
import SwiftUI

/// Messages-like chat UI for iOS Dialectics conversations.
/// Shows message bubbles in a ScrollView with text input at bottom.
struct MobileChatView: View {
    /// What the screen was opened with, which is all that's left to show if the
    /// conversation is deleted while it's up.
    private let openedConversation: ConversationGraph
    @Fetch private var currentConversation: ConversationGraph?
    @Dependency(\.defaultDatabase) private var database

    @Fetch(Library.Request()) private var library = Library()
    @State private var dialecticsService = DialecticsService()
    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy?

    init(conversation: ConversationGraph) {
        openedConversation = conversation
        _currentConversation = Fetch(
            wrappedValue: conversation,
            ConversationGraph.Request(id: conversation.id)
        )
    }

    private var conversation: ConversationGraph {
        currentConversation ?? openedConversation
    }

    private var seedItems: [ItemGraph] {
        library.items.filter { conversation.seedItemIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
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
                        }

                        // Streaming indicator
                        if dialecticsService.isGenerating {
                            streamingIndicator
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
            }

            if !seedItems.isEmpty {
                contextBanner
            }

            Divider()

            // Input area
            inputArea
        }
        .navigationTitle(conversation.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Input area

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            TextField("Message...", text: $inputText, axis: .vertical)
                .font(.groveBody)
                .lineLimit(1...5)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                #if os(iOS)
                .dropDestination(for: URL.self) { urls, _ in
                    handleItemDrop(urls: urls)
                }
                #endif

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.textPrimary : Color.textMuted)
            }
            .disabled(!canSend)
            .frame(minWidth: LayoutDimensions.minTouchTarget,
                   minHeight: LayoutDimensions.minTouchTarget)
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
                            .font(.system(size: 10))
                        Text(item.title)
                            .lineLimit(1)
                    }
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.bgCard)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
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
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
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
        inputText = ""

        Task {
            _ = await dialecticsService.sendMessage(
                userText: text,
                conversationID: conversation.id
            )
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = conversation.visibleMessages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Drop handling (P11.3)

    private func handleItemDrop(urls: [URL]) -> Bool {
        for url in urls {
            if url.scheme == "grove", url.host == "item" {
                if let uuid = UUID(uuidString: url.lastPathComponent) {
                    if let item = library.item(uuid) {
                        inputText = "Let's discuss \"\(item.title)\"."
                        addSeedItem(item.id)
                        return true
                    }
                }
            } else {
                // Regular URL — find item by sourceURL
                let urlString = url.absoluteString
                if let item = library.items.first(where: { $0.sourceURL == urlString }) {
                    inputText = "Let's discuss \"\(item.title)\"."
                    addSeedItem(item.id)
                    return true
                }
            }
        }
        return false
    }

    private func addSeedItem(_ itemID: Item.ID) {
        let conversationID = conversation.id
        database.attempt { db in
            try Conversation.modify(conversationID, in: db) {
                if !$0.seedItemIDs.contains(itemID) {
                    $0.seedItemIDs.append(itemID)
                }
            }
        }
    }

    // MARK: - Message actions (P6.7)

    private func saveAsReflection(_ message: ChatMessage) {
        // Save to the first seed item if available
        if let item = library.item(conversation.seedItemIDs.first) {
            _ = dialecticsService.saveAsReflection(
                content: message.content,
                itemTitle: item.title,
                blockType: .keyInsight,
                conversationID: conversation.id
            )
        }
    }

    private func saveAsNote(_ message: ChatMessage) {
        let title = String(message.content.prefix(60))
        _ = dialecticsService.saveAsNote(
            content: message.content,
            title: title,
            conversationID: conversation.id
        )
    }
}
