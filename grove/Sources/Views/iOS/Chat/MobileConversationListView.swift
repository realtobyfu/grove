import SwiftUI
import SwiftData

/// List of past Dialectics conversations with search, sorted by most recent.
/// Tap navigates to MobileChatView. New conversation button in toolbar.
struct MobileConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var dialecticsService = DialecticsService()
    @State private var searchText = ""
    @State private var routedConversation: Conversation?
    @State private var paywallPresentation: PaywallPresentation?

    var initialConversationID: UUID?

    private var activeConversations: [Conversation] {
        conversations.filter { !$0.isArchived && $0.isSavedToHistory }
    }

    private var visibleHistoryConversations: [Conversation] {
        guard entitlement.hasAccess(to: .fullHistory) else {
            return Array(activeConversations.prefix(20))
        }
        return activeConversations
    }

    private var isHistoryCapped: Bool {
        !entitlement.hasAccess(to: .fullHistory) && activeConversations.count > visibleHistoryConversations.count
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredConversations: [Conversation] {
        let query = trimmedSearchText
        guard !query.isEmpty else { return visibleHistoryConversations }
        return visibleHistoryConversations.filter {
            conversationMatchesSearch($0, query: query)
        }
    }

    var body: some View {
        Group {
            if activeConversations.isEmpty {
                emptyState
            } else {
                conversationList
            }
        }
        .background(Color.bgPrimary)
        .navigationTitle("Chat")
        .searchable(
            text: $searchText,
            prompt: entitlement.hasAccess(to: .fullHistory)
                ? "Search by title or message..."
                : "Search recent conversations..."
        )
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
        .sheet(item: $paywallPresentation) { presentation in
            ProPaywallView(presentation: presentation)
        }
        .onAppear {
            openInitialConversationIfNeeded()
        }
        .onChange(of: initialConversationID) { _, _ in
            openInitialConversationIfNeeded()
        }
        .onChange(of: conversations.count) { _, _ in
            openInitialConversationIfNeeded()
        }
        .navigationDestination(item: $routedConversation) { conversation in
            MobileChatView(conversation: conversation)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        ScrollView {
            GroveEmptyState(
                title: "No conversations yet.",
                detail: "Think something through with Chat. It can search your library, highlights and reflections.",
                actionTitle: "New conversation",
                action: startNewConversation
            )
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
        }
    }

    // MARK: - List

    private var conversationList: some View {
        List {
            if isHistoryCapped {
                historyCappedBanner
            }

            if filteredConversations.isEmpty {
                noSearchResultsRow
            }

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
                    .tint(Color.textTertiary)
                }
            }
            .listRowBackground(Color.bgPrimary)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        .navigationDestination(for: Conversation.self) { conversation in
            MobileChatView(conversation: conversation)
        }
    }

    private var historyCappedBanner: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Showing recent 20 conversations")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                Text("Upgrade to Pro for full searchable history.")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            Button("Unlock Pro") {
                paywallPresentation = paywallCoordinator.present(
                    feature: .fullHistory,
                    source: .chatHistory
                )
            }
            .buttonStyle(.grove(.secondary, size: .compact))
        }
        .padding(.vertical, Spacing.xs)
        .listRowBackground(Color.bgPrimary)
    }

    private var noSearchResultsRow: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("No search results")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
            Text("No matches for \"\(trimmedSearchText)\".")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, Spacing.sm)
        .listRowBackground(Color.bgPrimary)
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(conversation.displayTitle)
                .font(.groveListTitle)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text(rowMeta(for: conversation))
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutDimensions.minTouchTarget, alignment: .leading)
        .padding(.vertical, Spacing.xs)
    }

    /// "2h · 6 messages · Gardens": when, how long, and where, in one mono line.
    private func rowMeta(for conversation: Conversation) -> String {
        let count = conversation.visibleMessages.count
        var parts = [
            compactRelativeTime(from: conversation.updatedAt),
            count == 1 ? "1 message" : "\(count) messages",
        ]
        if let boardTitle = conversation.board?.title, !boardTitle.isEmpty {
            parts.append(boardTitle)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func startNewConversation() {
        guard entitlement.canUse(.dialectics) else {
            paywallPresentation = paywallCoordinator.present(
                feature: .dialectics,
                source: .dialecticsLimit
            )
            return
        }

        let conversation = dialecticsService.startConversation(
            trigger: .userInitiated,
            seedItems: [],
            board: nil,
            context: modelContext
        )
        routedConversation = conversation
    }

    private func deleteConversation(_ conversation: Conversation) {
        if routedConversation?.id == conversation.id {
            routedConversation = nil
        }
        DialecticsService.discardBoardProposal(forConversationID: conversation.id)
        modelContext.delete(conversation)
        try? modelContext.save()
    }

    private func conversationMatchesSearch(_ conversation: Conversation, query: String) -> Bool {
        if conversation.displayTitle.localizedStandardContains(query) {
            return true
        }
        return conversation.visibleMessages.contains { message in
            message.content.localizedStandardContains(query)
        }
    }

    private func compactRelativeTime(from date: Date) -> String {
        let elapsed = max(0, Int(Date.now.timeIntervalSince(date)))

        if elapsed < 3600 {
            let minutes = max(1, elapsed / 60)
            return "\(minutes)m"
        }

        if elapsed < 86_400 {
            let hours = elapsed / 3600
            return "\(hours)h"
        }

        if elapsed < 604_800 {
            let days = elapsed / 86_400
            return "\(days)d"
        }

        if elapsed < 2_592_000 {
            let weeks = elapsed / 604_800
            return "\(weeks)w"
        }

        if elapsed < 31_536_000 {
            let months = elapsed / 2_592_000
            return "\(months)mo"
        }

        let years = elapsed / 31_536_000
        return "\(years)y"
    }

    private func openInitialConversationIfNeeded() {
        guard let initialConversationID else { return }
        guard let conversation = conversations.first(where: { $0.id == initialConversationID }) else { return }
        routedConversation = conversation
    }
}
