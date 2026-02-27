import SwiftUI

/// Recent items and recent conversations sections on the Home screen.
struct HomeRecentItemsSection: View {
    let recentItems: [Item]
    @Binding var isCollapsed: Bool
    let onOpen: (Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(
                title: "RECENT ITEMS",
                count: recentItems.count,
                isCollapsed: $isCollapsed
            )

            if !isCollapsed {
                if recentItems.isEmpty {
                    Text("No items yet. Capture something to get started.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.vertical, Spacing.sm)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentItems) { item in
                            compactItemRow(item)
                            if item.id != recentItems.last?.id {
                                Divider().padding(.leading, Spacing.xl + Spacing.sm)
                            }
                        }
                    }
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.borderPrimary, lineWidth: 1)
                    )
                }
            }
        }
    }

    private func compactItemRow(_ item: Item) -> some View {
        Button {
            onOpen(item)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: item.type.iconName)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if let board = item.boards.first {
                        Text(board.title)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        Text("Unfiled")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                Text(item.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Conversations Section

struct HomeRecentConversationsSection: View {
    let recentConversations: [Conversation]
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(
                title: "RECENT CONVERSATIONS",
                count: recentConversations.count,
                isCollapsed: $isCollapsed
            )

            if !isCollapsed {
                VStack(spacing: 0) {
                    ForEach(recentConversations) { conversation in
                        conversationRow(conversation)
                        if conversation.id != recentConversations.last?.id {
                            Divider().padding(.leading, Spacing.xl + Spacing.sm)
                        }
                    }
                }
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                )
            }
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .groveOpenConversation,
                object: conversation
            )
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.displayTitle)
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if let last = conversation.visibleMessages.last {
                        Text(last.content)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(conversation.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.textMuted)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
