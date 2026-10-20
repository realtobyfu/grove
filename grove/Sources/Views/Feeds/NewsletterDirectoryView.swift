import SwiftUI
import SwiftData

/// Browsable catalog of hand-curated newsletters, ranked on-device by
/// relevance to the user's library (tag/keyword overlap, refined with
/// sentence-embedding similarity when available).
///
/// Laid out as a printed index rather than a deck of cards: one bordered
/// container, hairline rules between entries, serif names over a mono
/// domain/topic line. Actions stay quiet until the row is hovered.
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

    private func count(for topic: String?) -> Int {
        guard let topic else { return ranked.count }
        return ranked.filter { $0.entry.topics.contains(topic) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            topicFilterBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if visibleEntries.isEmpty {
                        emptyState
                    } else {
                        entryList
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            Text("Directory")
                .font(.groveTitleLarge)
                .foregroundStyle(Color.textPrimary)
            if !ranked.isEmpty {
                Text("\(visibleEntries.count)")
                    .font(.groveBadge)
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
            }

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
            .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
            #endif
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close directory")
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
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
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func topicChip(label: String, topic: String?) -> some View {
        FilterChip(label: label, count: count(for: topic), isActive: selectedTopic == topic) {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTopic = topic
            }
        }
    }

    // MARK: - Entries

    /// One card, hairline rules between rows — the settings sheet's row idiom.
    private var entryList: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, rankedEntry in
                if index > 0 {
                    Divider()
                        .padding(.leading, Spacing.md)
                }
                NewsletterDirectoryRow(
                    rankedEntry: rankedEntry,
                    isSubscribed: isSubscribed(rankedEntry.entry),
                    onSubscribe: { subscribe(rankedEntry.entry) },
                    onDismiss: { dismissEntry(rankedEntry.entry) }
                )
            }
        }
        .cardStyle()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(ranked.isEmpty ? "No newsletters" : "No matches")
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)
            if !ranked.isEmpty {
                Text("Try another topic.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .cardStyle()
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

// MARK: - Directory Row

private struct NewsletterDirectoryRow: View {
    let rankedEntry: RankedNewsletterEntry
    let isSubscribed: Bool
    let onSubscribe: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false

    private var entry: NewsletterCatalogEntry { rankedEntry.entry }

    /// Domain and topics on one mono line — the topics already have their own
    /// filter chips above, so they read as locators here, not as tags.
    private var locatorLine: String {
        ([entry.domain] + entry.topics).joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.groveListTitle)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(locatorLine)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)

                Text(entry.blurb)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)

            }

            Spacer(minLength: Spacing.sm)

            HStack(spacing: Spacing.xs) {
                if isSubscribed {
                    Label("Subscribed", systemImage: "checkmark")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    Button("Subscribe") {
                        onSubscribe()
                    }
                    .buttonStyle(GroveCompactButtonStyle(prominent: true))
                    #if os(iOS)
                    .frame(minHeight: LayoutDimensions.minTouchTarget)
                    #endif
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.groveMeta)
                        .foregroundStyle(isHovering ? Color.textPrimary : Color.textTertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .opacity(isHovering ? 1 : 0)
                #else
                .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                #endif
                .accessibilityLabel("Hide \(entry.title)")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
