import SwiftUI
import SwiftData

/// iOS Home screen — conversation starters, recent items, and nudge banners.
/// iPhone: vertical ScrollView. iPad (P7.4): two-column layout via size class.
struct MobileHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Item.lastEngagedAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Nudge.createdAt, order: .reverse) private var allNudges: [Nudge]

    @State private var starterService = ConversationStarterService.shared
    @State private var dialecticsService = DialecticsService()

    private var recentItems: [Item] {
        Array(allItems.filter { $0.status == .active || $0.status == .inbox }.prefix(6))
    }

    private var pendingNudges: [Nudge] {
        allNudges.filter { $0.status == .pending || $0.status == .shown }
    }

    var body: some View {
        ScrollView {
            if horizontalSizeClass == .regular {
                // iPad: two-column layout
                HStack(alignment: .top, spacing: Spacing.xl) {
                    VStack(spacing: Spacing.lg) {
                        startersSection
                        nudgesSection
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: Spacing.lg) {
                        recentItemsSection
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .padding(.top, Spacing.lg)
            } else {
                // iPhone: single column
                VStack(spacing: Spacing.lg) {
                    startersSection
                    recentItemsSection
                    nudgesSection
                }
                .padding(.horizontal, LayoutDimensions.contentPaddingH)
                .padding(.top, Spacing.md)
            }
        }
        .navigationTitle("Home")
        .task {
            await starterService.refresh(items: allItems)
        }
    }

    // MARK: - Conversation starters

    @ViewBuilder
    private var startersSection: some View {
        let bubbles = Array(starterService.bubbles.prefix(3))
        if !bubbles.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Conversation Starters")
                    .sectionHeaderStyle()

                ForEach(bubbles) { bubble in
                    MobileStarterCard(bubble: bubble) {
                        startConversation(with: bubble)
                    }
                }
            }
        }
    }

    // MARK: - Recent items

    @ViewBuilder
    private var recentItemsSection: some View {
        if !recentItems.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Recent")
                    .sectionHeaderStyle()

                ForEach(recentItems) { item in
                    MobileItemCardView(item: item)
                }
            }
        }
    }

    // MARK: - Nudge banners

    @ViewBuilder
    private var nudgesSection: some View {
        if !pendingNudges.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Nudges")
                    .sectionHeaderStyle()

                ForEach(pendingNudges) { nudge in
                    MobileNudgeBanner(
                        nudge: nudge,
                        onOpen: {
                            nudge.status = .actedOn
                            try? modelContext.save()
                        },
                        onDismiss: {
                            withAnimation {
                                nudge.status = .dismissed
                                try? modelContext.save()
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func startConversation(with bubble: PromptBubble) {
        let seedItems = allItems.filter { bubble.clusterItemIDs.contains($0.id) }
        let conversation = dialecticsService.startConversation(
            trigger: .userInitiated,
            seedItems: seedItems,
            board: nil,
            context: modelContext
        )
        // Send the prompt as first user message
        Task {
            _ = await dialecticsService.sendMessage(
                userText: bubble.prompt,
                conversation: conversation,
                context: modelContext
            )
        }
    }
}
