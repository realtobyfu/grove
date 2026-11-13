import SwiftUI

/// "Think Next" section on the Home screen — the single surface for agentic
/// suggestions: a conversation starter.
/// With nothing to suggest, the section renders nothing at all rather than
/// padding Home with a generic card.
struct HomeDiscussionSection: View {
    let discussionBubbles: [PromptBubble]
    @Binding var isCollapsed: Bool
    let onOpenChat: (PromptBubble) -> Void
    let onStartWriting: (PromptBubble) -> Void
    let onDismissBubble: (PromptBubble) -> Void

    var body: some View {
        if let bubble = discussionBubbles.first {
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
                    StarterCard(
                        bubble: bubble,
                        onOpenChat: { onOpenChat(bubble) },
                        onStartWriting: { onStartWriting(bubble) },
                        onDismiss: { onDismissBubble(bubble) }
                    )
                }
            }
        }
    }
}
