import SwiftUI

/// Discussion suggestions section on the Home screen with conversation starter cards.
struct HomeDiscussionSection: View {
    let discussionBubbles: [PromptBubble]
    @Binding var isCollapsed: Bool
    let onNewConversation: () -> Void
    let onBubbleTap: (PromptBubble) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                HomeSectionHeader(
                    title: "THINK NEXT",
                    count: 1,
                    isCollapsed: $isCollapsed
                )

                Spacer()
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
}
