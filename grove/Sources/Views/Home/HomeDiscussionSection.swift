import SwiftUI

/// "Think Next" section on the Home screen — the single surface for agentic
/// suggestions: a resurfaced item worth revisiting and a conversation starter.
/// With nothing to suggest, the section renders nothing at all rather than
/// padding Home with a generic card.
struct HomeDiscussionSection: View {
    let resurfaceNudge: Nudge?
    let discussionBubbles: [PromptBubble]
    @Binding var isCollapsed: Bool
    let onBubbleTap: (PromptBubble) -> Void
    let onOpenNudge: (Nudge) -> Void
    let onDismissNudge: (Nudge) -> Void
    let onDismissBubble: (PromptBubble) -> Void

    private var cardCount: Int {
        (resurfaceNudge != nil ? 1 : 0) + (discussionBubbles.first != nil ? 1 : 0)
    }

    var body: some View {
        if cardCount > 0 {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    HomeSectionHeader(
                        title: "THINK NEXT",
                        count: cardCount,
                        isCollapsed: $isCollapsed
                    )

                    Spacer()
                }

                if !isCollapsed {
                    if let nudge = resurfaceNudge {
                        SuggestedConversationCard(
                            label: "REVISIT",
                            title: nudge.displayMessage,
                            onDismiss: { onDismissNudge(nudge) }
                        ) {
                            onOpenNudge(nudge)
                        }
                    }

                    if let bubble = discussionBubbles.first {
                        SuggestedConversationCard(
                            label: bubble.label,
                            title: bubble.prompt,
                            onDismiss: { onDismissBubble(bubble) }
                        ) {
                            onBubbleTap(bubble)
                        }
                    }
                }
            }
        }
    }
}
