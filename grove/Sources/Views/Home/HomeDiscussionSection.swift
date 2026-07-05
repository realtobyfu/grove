import SwiftUI

/// Discussion suggestions section on the Home screen with conversation starter cards.
struct HomeDiscussionSection: View {
    let discussionBubbles: [PromptBubble]
    @Binding var isCollapsed: Bool
    let onNewConversation: () -> Void
    let onBubbleTap: (PromptBubble) -> Void
    var allItems: [Item] = []
    var starterService: ConversationStarterService?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                HomeSectionHeader(
                    title: "THINK NEXT",
                    count: 1,
                    isCollapsed: $isCollapsed
                )

                Spacer()

                #if DEBUG
                if let starterService {
                    debugRefreshButton(starterService: starterService)
                }
                #endif
            }

            if !isCollapsed {
                if let bubble = discussionBubbles.first {
                    SuggestedConversationCard(
                        label: bubble.label,
                        title: bubble.prompt
                    ) {
                        onBubbleTap(bubble)
                    }
                } else {
                    SuggestedConversationCard(
                        label: "CHAT",
                        title: "New Conversation",
                        subtitle: "Start an open-ended dialectical session",
                        icon: "bubble.left.and.bubble.right"
                    ) {
                        onNewConversation()
                    }
                }
            }
        }
    }

    #if DEBUG
    private func debugRefreshButton(starterService: ConversationStarterService) -> some View {
        Button {
            Task {
                await starterService.forceRefresh(items: allItems)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                Text("Refresh")
            }
            .font(.groveMeta)
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.borderPrimary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Force-refresh discussion suggestions (debug)")
    }
    #endif
}
