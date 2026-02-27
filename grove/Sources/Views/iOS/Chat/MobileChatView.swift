import SwiftUI
import SwiftData

/// Messages-like chat UI for iOS Dialectics conversations.
/// Shows message bubbles in a ScrollView with text input at bottom.
struct MobileChatView: View {
    @Bindable var conversation: Conversation
    @Environment(\.modelContext) private var modelContext

    @Query private var allItemsForContext: [Item]
    @State private var dialecticsService = DialecticsService()
    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy?

    private var seedItems: [Item] {
        allItemsForContext.filter { conversation.seedItemIDs.contains($0.id) }
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
                conversation: conversation,
                context: modelContext
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
