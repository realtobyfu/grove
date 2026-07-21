import SwiftUI
import SwiftData

/// The newsletter reading surface: current and past issues from subscribed
/// feeds, organized by newsletter, with read/unread state. Issues open in the
/// standard reader; keeping one promotes it into the library proper.
struct NewsletterInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \FeedSource.createdAt) private var allSources: [FeedSource]

    @State private var showSubscriptions = false
    @State private var selectedSourceID: UUID?
    /// Sources whose full history is shown; others collapse to the first few.
    @State private var expandedSourceIDs: Set<UUID> = []

    /// Issues shown per newsletter before "Show all" kicks in.
    private static let collapsedIssueLimit = 3

    var onOpenItem: ((Item) -> Void)? = nil

    // MARK: - Data

    /// Formatter creation is expensive; one instance for the whole view.
    private static let isoDateFormatter = ISO8601DateFormatter()

    private struct DatedIssue: Identifiable {
        let item: Item
        let publishedAt: Date
        var id: UUID { item.id }
    }

    /// One newsletter with its issues newest-first and a precomputed
    /// unread count.
    private struct SourceGroup: Identifiable {
        let source: FeedSource
        let issues: [DatedIssue]
        let unread: Int
        var latest: Date { issues.first?.publishedAt ?? .distantPast }
        var id: UUID { source.id }
    }

    /// Single pass over the store, computed once per render. Every chip,
    /// count, and section reads from this snapshot — no per-callsite
    /// re-filtering or re-sorting of the item list.
    private var groups: [SourceGroup] {
        var bySource: [String: [DatedIssue]] = [:]
        for item in allItems where item.isNewsletterIssue && item.status != .dismissed {
            let date = item.metadata["publishedAt"]
                .flatMap { Self.isoDateFormatter.date(from: $0) } ?? item.createdAt
            bySource[item.metadata["feedSourceID"] ?? "", default: []]
                .append(DatedIssue(item: item, publishedAt: date))
        }
        guard !bySource.isEmpty else { return [] }

        return allSources
            .compactMap { source -> SourceGroup? in
                guard let dated = bySource[source.id.uuidString] else { return nil }
                let sorted = dated.sorted { $0.publishedAt > $1.publishedAt }
                let unread = sorted.filter { !$0.item.isFeedIssueRead }.count
                return SourceGroup(source: source, issues: sorted, unread: unread)
            }
            .sorted { $0.latest > $1.latest }
    }

    private func visibleGroups(in groups: [SourceGroup]) -> [SourceGroup] {
        guard let selectedSourceID else { return groups }
        return groups.filter { $0.id == selectedSourceID }
    }

    // MARK: - Body

    var body: some View {
        // Snapshot once; children receive data, not queries.
        let groups = groups
        let totalUnread = groups.reduce(0) { $0 + $1.unread }

        Group {
            if groups.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    sourceFilterBar(groups: groups, totalUnread: totalUnread)
                    Divider()
                    issueList(groups: groups)
                }
            }
        }
        .background(Color.bgPrimary)
        .navigationTitle("Newsletters")
        .sheet(isPresented: $showSubscriptions) {
            SubscriptionsSettingsView(showsHeader: true)
                #if os(macOS)
                .frame(width: 520, height: 620)
                #endif
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No newsletter issues yet", systemImage: "newspaper")
        } description: {
            Text("Subscribe to a newsletter and new issues will appear here.")
        } actions: {
            Button("Manage subscriptions") {
                showSubscriptions = true
            }
        }
    }

    // MARK: - Source Filter

    /// Chip bar for filtering by newsletter, with the section's quiet
    /// actions (mark all read, manage subscriptions) at the trailing edge.
    private func sourceFilterBar(groups: [SourceGroup], totalUnread: Int) -> some View {
        HStack(spacing: Spacing.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    FilterChip(label: "All", count: totalUnread, isActive: selectedSourceID == nil) {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedSourceID = nil }
                    }
                    ForEach(groups) { group in
                        FilterChip(
                            label: group.source.title ?? group.source.domain,
                            count: group.unread,
                            isActive: selectedSourceID == group.id
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedSourceID = group.id }
                        }
                    }
                }
                .padding(.vertical, Spacing.sm)
            }

            Spacer(minLength: 0)

            HStack(spacing: Spacing.sm) {
                if totalUnread > 0 {
                    Button {
                        markAllRead(groups: groups)
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.groveBody)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Mark all issues as read")
                    .accessibilityLabel("Mark all issues as read")
                }

                Button {
                    showSubscriptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.groveBody)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Manage subscriptions")
                .accessibilityLabel("Manage subscriptions")
            }
        }
        .padding(.horizontal, LayoutDimensions.contentPaddingH)
    }

    // MARK: - Issue List

    private func issueList(groups: [SourceGroup]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if selectedSourceID == nil {
                    // "All": group into a section per newsletter.
                    ForEach(groups) { group in
                        sourceSection(group)
                    }
                } else if let group = groups.first(where: { $0.id == selectedSourceID }) {
                    sourceSection(group, showsHeader: false)
                }
            }
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.vertical, Spacing.lg)
        }
    }

    @ViewBuilder
    private func sourceSection(_ group: SourceGroup, showsHeader: Bool = true) -> some View {
        // Collapse long histories in the "All" view; a single-newsletter
        // filter always shows everything.
        let isCollapsible = showsHeader && group.issues.count > Self.collapsedIssueLimit
        let isExpanded = !isCollapsible || expandedSourceIDs.contains(group.id)
        let visibleRows = isExpanded ? group.issues : Array(group.issues.prefix(Self.collapsedIssueLimit))

        VStack(alignment: .leading, spacing: Spacing.sm) {
            if showsHeader {
                HStack(spacing: Spacing.sm) {
                    Text(group.source.title ?? group.source.domain)
                        .sectionHeaderStyle()
                    if group.unread > 0 {
                        Text("\(group.unread)")
                            .font(.groveBadge)
                            .foregroundStyle(Color.textTertiary)
                            .monospacedDigit()
                    }
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, issue in
                    if index > 0 {
                        Divider()
                            .padding(.leading, Spacing.lg)
                    }
                    issueRow(issue)
                }

                if isCollapsible {
                    Divider()
                        .padding(.leading, Spacing.lg)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedSourceIDs.remove(group.id)
                            } else {
                                expandedSourceIDs.insert(group.id)
                            }
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text(isExpanded ? "Show less" : "Show all \(group.issues.count)")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .medium))
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #if os(iOS)
                    .frame(minHeight: LayoutDimensions.minTouchTarget)
                    #endif
                }
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private func issueRow(_ issue: DatedIssue) -> some View {
        let item = issue.item
        let row = NewsletterIssueRow(
            item: item,
            publishedAt: issue.publishedAt,
            onKeep: { keep(item) },
            onToggleRead: { toggleRead(item) },
            onHide: { hide(item) }
        )

        if let onOpenItem {
            row
                .contentShape(Rectangle())
                .onTapGesture {
                    markRead(item)
                    onOpenItem(item)
                }
                .accessibilityLabel("Open \(item.title)")
        } else {
            #if os(iOS)
            NavigationLink {
                MobileItemReaderView(item: item)
                    .onAppear { markRead(item) }
            } label: {
                row
            }
            .buttonStyle(.plain)
            #else
            row
            #endif
        }
    }

    // MARK: - Actions

    private func markRead(_ item: Item) {
        guard !item.isFeedIssueRead else { return }
        item.isFeedIssueRead = true
        try? modelContext.save()
    }

    private func toggleRead(_ item: Item) {
        item.isFeedIssueRead.toggle()
        try? modelContext.save()
    }

    private func markAllRead(groups: [SourceGroup]) {
        for group in visibleGroups(in: groups) {
            for issue in group.issues where !issue.item.isFeedIssueRead {
                issue.item.isFeedIssueRead = true
            }
        }
        try? modelContext.save()
    }

    /// Promote an issue into the library: it stops being an ephemeral feed
    /// suggestion and joins the normal item lifecycle (boards, resurfacing).
    /// Kept issues get real content backfilled — page metadata plus an
    /// overview from the configured LLM (Apple Intelligence by default).
    private func keep(_ item: Item) {
        recordSignal(for: item, kept: true)
        item.promoteFromFeedSuggestionIfNeeded()
        try? modelContext.save()

        if (item.content ?? "").isEmpty, let urlString = item.sourceURL {
            let context = modelContext
            let itemID = item.id
            Task {
                await ItemMetadataEnricher().enrichPromotedIssue(
                    itemID: itemID,
                    urlString: urlString,
                    context: context
                )
            }
        }
    }

    /// Hide an issue from newsletter history (and count a dismissal signal
    /// toward the source's auto-throttle).
    private func hide(_ item: Item) {
        recordSignal(for: item, kept: false)
        withAnimation(.easeOut(duration: 0.25)) {
            item.status = .dismissed
            item.metadata["suggestionDismissed"] = "true"
            item.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func recordSignal(for item: Item, kept: Bool) {
        guard item.isFeedSuggestion,
              let idString = item.metadata["feedSourceID"],
              let id = UUID(uuidString: idString) else { return }
        if kept {
            FeedPreferencesStore.recordKeep(sourceID: id)
        } else {
            FeedPreferencesStore.recordDismissal(sourceID: id)
        }
    }
}

// MARK: - Issue Row

/// Compact mail-style row: unread dot, title, publish date. Kept issues show
/// a bookmark; hover (macOS) reveals keep/hide, context menu carries the rest.
private struct NewsletterIssueRow: View {
    let item: Item
    let publishedAt: Date
    let onKeep: () -> Void
    let onToggleRead: () -> Void
    let onHide: () -> Void

    @State private var isHovering = false

    private var isUnread: Bool { !item.isFeedIssueRead }
    private var isKept: Bool { !item.isFeedSuggestion }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(isUnread ? Color.textPrimary : Color.clear)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(isUnread ? .groveBodyMedium : .groveBody)
                    .foregroundStyle(isUnread ? Color.textPrimary : Color.textSecondary)
                    .lineLimit(2)

                HStack(spacing: Spacing.xs) {
                    Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)

                    if isKept {
                        Text("·")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textMuted)
                        Label("In library", systemImage: "bookmark.fill")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Spacer(minLength: Spacing.sm)

            #if os(macOS)
            if isHovering {
                HStack(spacing: Spacing.sm) {
                    if !isKept {
                        Button("Keep") {
                            onKeep()
                        }
                        .font(.groveBodySmall)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.textSecondary)
                        .help("Save to library")
                    }

                    Button {
                        onHide()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Hide issue")
                }
                .transition(.opacity)
            }
            #endif
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm + 2)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            if !isKept {
                Button {
                    onKeep()
                } label: {
                    Label("Keep in Library", systemImage: "bookmark")
                }
            }
            Button {
                onToggleRead()
            } label: {
                Label(
                    isUnread ? "Mark as Read" : "Mark as Unread",
                    systemImage: isUnread ? "envelope.open" : "envelope.badge"
                )
            }
            Divider()
            Button(role: .destructive) {
                onHide()
            } label: {
                Label("Hide Issue", systemImage: "xmark.circle")
            }
        }
    }
}
