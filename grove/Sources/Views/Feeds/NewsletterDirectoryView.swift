import SwiftUI
import SwiftData

/// Browsable catalog of hand-curated newsletters, ranked on-device by
/// relevance to the user's library (tag/keyword overlap, refined with
/// sentence-embedding similarity when available).
struct NewsletterDirectoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var sources: [FeedSource]

    @State private var ranked: [RankedNewsletterEntry] = []
    @State private var selectedTopic: String?

    private var visibleEntries: [RankedNewsletterEntry] {
        guard let selectedTopic else { return ranked }
        return ranked.filter { $0.entry.topics.contains(selectedTopic) }
    }

    private var allTopics: [String] {
        Array(Set(ranked.flatMap { $0.entry.topics })).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            topicFilterBar
            Divider()

            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    if visibleEntries.isEmpty {
                        Text("Nothing here — every newsletter in this topic was dismissed.")
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textTertiary)
                            .padding(.vertical, Spacing.lg)
                    }

                    ForEach(visibleEntries) { rankedEntry in
                        NewsletterDirectoryCard(
                            rankedEntry: rankedEntry,
                            isSubscribed: isSubscribed(rankedEntry.entry),
                            onSubscribe: { subscribe(rankedEntry.entry) },
                            onDismiss: { dismissEntry(rankedEntry.entry) }
                        )
                    }
                }
                .padding(Spacing.md)
            }
        }
        .background(Color.bgPrimary)
        .task {
            await loadRanking()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "newspaper")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
            Text("Newsletter Directory")
                .font(.groveTitleLarge)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            #if os(iOS)
            .frame(minWidth: 44, minHeight: 44)
            #endif
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close directory")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Topic Filter

    private var topicFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                topicChip(label: "All", topic: nil)
                ForEach(allTopics, id: \.self) { topic in
                    topicChip(label: topic, topic: topic)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func topicChip(label: String, topic: String?) -> some View {
        let isActive = selectedTopic == topic
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTopic = topic
            }
        } label: {
            Text(label)
                .font(.groveTag)
                .foregroundStyle(isActive ? Color.textInverse : Color.textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(isActive ? Color.textPrimary : Color.bgCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isActive ? Color.clear : Color.borderTag, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .frame(minHeight: 44)
        #endif
    }

    // MARK: - Subscription State

    private func isSubscribed(_ entry: NewsletterCatalogEntry) -> Bool {
        sources.contains { $0.feedURL == entry.feedURL && $0.isEnabled }
    }

    private func subscribe(_ entry: NewsletterCatalogEntry) {
        FeedSubscriptionService.subscribe(
            feedURL: entry.feedURL,
            domain: entry.domain,
            title: entry.title,
            in: modelContext
        )
    }

    private func dismissEntry(_ entry: NewsletterCatalogEntry) {
        FeedPreferencesStore.dismissCatalogEntry(entry.id)
        withAnimation(.easeOut(duration: 0.2)) {
            ranked.removeAll { $0.entry.id == entry.id }
        }
    }

    // MARK: - Ranking

    private func loadRanking() async {
        let entries = NewsletterCatalog.entries.filter {
            !FeedPreferencesStore.isCatalogEntryDismissed($0.id)
        }

        // User signal: tags weighted by how many items carry them, plus
        // recent item titles.
        let tags: [Tag] = (try? modelContext.fetch(FetchDescriptor<Tag>())) ?? []
        let userTags = tags
            .map { NewsletterRanker.UserTag(name: $0.name.lowercased(), weight: $0.items.count) }
            .filter { $0.weight > 0 }

        var itemDescriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        itemDescriptor.fetchLimit = 50
        let recentTitles = ((try? modelContext.fetch(itemDescriptor)) ?? []).map(\.title)

        let keywordRanked = NewsletterRanker.rank(
            entries: entries,
            userTags: userTags,
            recentTitles: recentTitles
        )
        ranked = keywordRanked

        // Second pass: embedding similarity against a compact profile text.
        let topTagNames = userTags.sorted { $0.weight > $1.weight }.prefix(15).map(\.name)
        let profileText = (topTagNames + recentTitles.prefix(20)).joined(separator: ", ")
        let refined = await NewsletterRanker.refine(keywordRanked, profileText: profileText)
        // Re-drop anything dismissed while the embedding pass was awaiting, so a
        // card the user tapped X on doesn't reappear from the stale snapshot.
        ranked = refined.filter { !FeedPreferencesStore.isCatalogEntryDismissed($0.entry.id) }
    }
}

// MARK: - Directory Card

private struct NewsletterDirectoryCard: View {
    let rankedEntry: RankedNewsletterEntry
    let isSubscribed: Bool
    let onSubscribe: () -> Void
    let onDismiss: () -> Void

    private var entry: NewsletterCatalogEntry { rankedEntry.entry }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.groveItemTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text(entry.domain)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .frame(minWidth: 44, minHeight: 44)
                #endif
                .accessibilityLabel("Hide \(entry.title)")
            }

            Text(entry.blurb)
                .font(.groveBodySecondary)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let reason = rankedEntry.reason {
                Text(reason)
                    .font(.groveGhostText)
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: Spacing.xs) {
                ForEach(entry.topics, id: \.self) { topic in
                    Text(topic)
                        .font(.groveTag)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 2)
                        .overlay(
                            Capsule().stroke(Color.borderTag, lineWidth: 1)
                        )
                }

                Spacer()

                if isSubscribed {
                    Label("Subscribed", systemImage: "checkmark")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Button("Subscribe") {
                        onSubscribe()
                    }
                    .font(.groveBodySmall)
                    .buttonStyle(.bordered)
                    #if os(iOS)
                    .frame(minHeight: 44)
                    #endif
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
    }
}
