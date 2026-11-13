import SwiftUI

struct BoardSuggestionsView: View {
    let suggestions: [PromptBubble]
    @Binding var isSuggestionsCollapsed: Bool
    let onOpenChat: (PromptBubble) -> Void
    let onStartWriting: (PromptBubble) -> Void
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                HomeSectionHeader(
                    title: "DISCUSSION SUGGESTIONS",
                    count: suggestions.count,
                    isCollapsed: $isSuggestionsCollapsed
                )

                Spacer()

                #if DEBUG
                if let onRefresh {
                    Button {
                        onRefresh()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control)
                                .strokeBorder(Color.borderPrimary, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Force-refresh discussion suggestions (debug)")
                }
                #endif
            }

            if !isSuggestionsCollapsed {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320, maximum: 400), spacing: Spacing.md, alignment: .top)],
                    spacing: Spacing.md
                ) {
                    ForEach(suggestions) { bubble in
                        StarterCard(
                            bubble: bubble,
                            onOpenChat: { onOpenChat(bubble) },
                            onStartWriting: { onStartWriting(bubble) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, Spacing.sm)
    }
}
