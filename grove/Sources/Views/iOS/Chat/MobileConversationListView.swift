import SwiftUI
import SwiftData

/// List of past Dialectics conversations with search, sorted by most recent.
/// Tap navigates to MobileChatView. New conversation button in toolbar.
struct MobileConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var dialecticsService = DialecticsService()
    @State private var searchText = ""

    private var filteredConversations: [Conversation] {
        let active = conversations.filter { !$0.isArchived }
        if searchText.isEmpty { return active }
        return active.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.messages.contains { msg in
                msg.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        Group {
            if conversations.filter({ !$0.isArchived }).isEmpty {
                ContentUnavailableView {
                    Label("No Conversations", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start a Dialectics conversation to explore your ideas.")
                }
            } else {
                conversationList
            }
        }
        .navigationTitle("Chat")
        .searchable(text: $searchText, prompt: "Search conversations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    startNewConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New conversation")
            }
        }
    }

    // MARK: - List

    private var conversationList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                NavigationLink(value: conversation) {
                    conversationRow(conversation)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteConversation(conversation)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: Conversation.self) { conversation in
            MobileChatView(conversation: conversation)
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(conversation.displayTitle)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(conversation.updatedAt, style: .relative)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
            }

            if let lastMessage = conversation.lastMessage {
                Text(lastMessage.content)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
        }
        .frame(minHeight: LayoutDimensions.minTouchTarget)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Actions

    private func startNewConversation() {
        _ = dialecticsService.startConversation(
            trigger: .userInitiated,
            seedItems: [],
            board: nil,
            context: modelContext
        )
    }

    private func deleteConversation(_ conversation: Conversation) {
        modelContext.delete(conversation)
        try? modelContext.save()
    }
}
