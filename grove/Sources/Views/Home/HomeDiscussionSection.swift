import SwiftUI

/// "Think next" in Today's Yours column — the single surface for agentic
/// suggestions: a conversation starter.
/// With nothing to suggest, the section renders nothing at all rather than
/// padding Today with a generic card.
struct HomeDiscussionSection: View {
    let discussionBubbles: [PromptBubble]
    let onOpenChat: (PromptBubble) -> Void
    let onStartWriting: (PromptBubble) -> Void
    let onDismissBubble: (PromptBubble) -> Void

    var body: some View {
        if let bubble = discussionBubbles.first {
            VStack(alignment: .leading, spacing: 0) {
                TodaySectionHeader(title: "Think next")

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
