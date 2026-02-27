import SwiftUI
import SwiftData

/// Popover displaying a searchable list of conversations with keyboard navigation.
struct ConversationListPopover: View {
    let conversations: [Conversation]
    let filteredConversations: [Conversation]
    let isHistoryCapped: Bool
    let trimmedQuery: String
    @Binding var searchQuery: String
    @Binding var selectionID: UUID?
    let entitlement: EntitlementService
    var onSelectConversation: (Conversation) -> Void
    var onDeleteConversation: (Conversation) -> Void
    var onUnlockPro: () -> Void
    var onPrepare: () -> Void
    var onSyncSelection: () -> Void

    @FocusState private var isSearchFocused: Bool

    private var filteredIDs: [UUID] {
        filteredConversations.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CONVERSATIONS")
                .sectionHeaderStyle()
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

            Divider()

            searchField

            Divider()

            if conversations.isEmpty {
                Text("No conversations yet.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(Spacing.md)
            } else if filteredConversations.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("No search results")
                        .font(.groveBody)
                        .foregroundStyle(Color.textSecondary)
                    Text("No matches for \"\(trimmedQuery)\".")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(Spacing.md)
            } else {
                if isHistoryCapped {
                    historyCappedBanner
                    Divider()
                }

                conversationScrollList
            }
        }
        .frame(width: 320)
        .onAppear {
            onPrepare()
            Task { @MainActor in
                isSearchFocused = true
            }
        }
        .onChange(of: searchQuery) { _, _ in
            onSyncSelection()
        }
        .onChange(of: filteredIDs) { _, _ in
            onSyncSelection()
        }
        .onKeyPress(.upArrow) {
            moveSelection(offset: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(offset: 1)
            return .handled
        }
        .onKeyPress(.return) {
            openSelectedConversation()
            return .handled
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            TextField(
                entitlement.hasAccess(to: .fullHistory)
                    ? "Search by title or message..."
                    : "Search recent conversations...",
                text: $searchQuery
            )
            .textFieldStyle(.plain)
            .font(.groveBody)
            .focused($isSearchFocused)
            .onSubmit {
                openSelectedConversation()
            }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear conversation search")
                .accessibilityHint("Clears the current conversation query.")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - History Capped Banner

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
                onUnlockPro()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Conversation List

    private var conversationScrollList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredConversations) { conv in
                        HStack(spacing: Spacing.xs) {
                            Button {
                                onSelectConversation(conv)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(conv.displayTitle)
                                            .font(.groveBody)
                                            .foregroundStyle(Color.textPrimary)
                                            .lineLimit(1)
                                        HStack(spacing: 4) {
                                            Text(conv.trigger.rawValue)
                                                .font(.groveBadge)
                                                .foregroundStyle(Color.textTertiary)
                                            Text(conv.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.groveMeta)
                                                .foregroundStyle(Color.textTertiary)
                                        }
                                    }
                                    Spacer()
                                    Text("\(conv.visibleMessages.count) msgs")
                                        .font(.groveBadge)
                                        .foregroundStyle(Color.textMuted)
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .contentShape(Rectangle())
                                .selectedItemStyle(selectionID == conv.id)
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                onDeleteConversation(conv)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.groveBodySmall)
                                    .foregroundStyle(Color.textMuted)
                            }
                            .buttonStyle(.plain)
                            .help("Delete conversation")
                            .accessibilityLabel("Delete conversation \(conv.displayTitle)")
                            .accessibilityHint("Permanently removes this conversation.")
                            .padding(.trailing, Spacing.sm)
                        }
                        .id(conv.id)
                        Divider().padding(.leading, Spacing.md)
                    }
                }
            }
            .onChange(of: selectionID) { _, newID in
                guard let selectedID = newID else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
        .frame(maxHeight: 300)
    }

    // MARK: - Keyboard Navigation

    private func moveSelection(offset: Int) {
        let ids = filteredIDs
        guard !ids.isEmpty else {
            selectionID = nil
            return
        }

        guard let currentID = selectionID,
              let currentIndex = ids.firstIndex(of: currentID) else {
            selectionID = ids.first
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), ids.count - 1)
        selectionID = ids[nextIndex]
    }

    private func openSelectedConversation() {
        guard let selectedID = selectionID,
              let conversation = filteredConversations.first(where: { $0.id == selectedID }) else { return }
        onSelectConversation(conversation)
    }
}
