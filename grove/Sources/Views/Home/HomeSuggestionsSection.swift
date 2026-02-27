import SwiftUI

/// Suggested reading / connection suggestions section on the Home screen.
struct HomeSuggestionsSection: View {
    let rankedSuggestions: [SuggestionRankingService.ScoredSuggestion]
    @Binding var isCollapsed: Bool
    let onAdd: (Item) -> Void
    let onDismiss: (Item) -> Void
    let onOpen: (Item) -> Void
    let onExplorePro: () -> Void

    @Environment(EntitlementService.self) private var entitlement

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(
                title: "SUGGESTED READING",
                count: rankedSuggestions.count,
                isCollapsed: $isCollapsed
            )

            if !isCollapsed {
                if !entitlement.canUse(.suggestedArticles) {
                    suggestionsPaywallTeaser
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 320, maximum: 400), spacing: Spacing.md)],
                        spacing: Spacing.md
                    ) {
                        ForEach(Array(rankedSuggestions.prefix(5))) { scored in
                            SuggestedArticleCard(
                                item: scored.item,
                                score: scored.score,
                                onAdd: { onAdd(scored.item) },
                                onDismiss: { onDismiss(scored.item) },
                                onOpen: { onOpen(scored.item) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var suggestionsPaywallTeaser: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("PRO")
                    .font(.groveBadge)
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)
                Text("Unlock suggested articles")
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                Text("Get AI-curated articles from sources you already trust.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Explore Pro") {
                onExplorePro()
            }
            .buttonStyle(HomePrimaryButtonStyle())
        }
        .padding(Spacing.md)
        .background(Color.bgCard)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
    }
}
