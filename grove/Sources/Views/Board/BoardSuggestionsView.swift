import SwiftUI

struct BoardSuggestionsView: View {
    let suggestions: [PromptBubble]
    @Binding var isSuggestionsCollapsed: Bool
    let onSelectSuggestion: (PromptBubble) -> Void
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

            if !isSuggestionsCollapsed {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320, maximum: 400), spacing: Spacing.md)],
                    spacing: Spacing.md
                ) {
                    ForEach(suggestions) { bubble in
                        SuggestedConversationCard(
                            label: bubble.label,
                            title: bubble.prompt
                        ) {
                            onSelectSuggestion(bubble)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, Spacing.sm)
    }
}
