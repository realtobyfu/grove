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
    @State private var showDirectory = false
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
                    followBar
                    sourceFilterBar(groups: groups, totalUnread: totalUnread)
                    Divider()
                    issueList(groups: groups)
                }
            }
        }
        .background(Color.bgPrimary)
        .navigationTitle("Following")
        .sheet(isPresented: $showSubscriptions) {
            SubscriptionsSettingsView(showsHeader: true)
                #if os(macOS)
                .frame(width: 520, height: 620)
                #endif
        }
        .sheet(isPresented: $showDirectory) {
            NewsletterDirectoryView()
                #if os(macOS)
                .frame(width: 560, height: 640)
                #endif
        }
    }

    // MARK: - Follow Bar

    /// Always-visible entry point for following something new — the same
    /// paste-a-URL gesture as the Home capture bar, scoped to feeds.
    private var followBar: some View {
        FollowFeedBar(onBrowseDirectory: { showDirectory = true })
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xs)
    }

    // MARK: - Empty State

    /// First-run surface: the follow input is the hero, with the directory
    /// as the browsing alternative for people who don't have a URL in mind.
    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                FollowFeedBar()

                Button {
                    showDirectory = true
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "newspaper")
                            .font(.groveBodyLarge)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Browse directory")
                                .font(.groveBodyMedium)
                                .foregroundStyle(Color.textPrimary)
                        }

                        Spacer(minLength: Spacing.sm)

                        Image(systemName: "chevron.right")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cardStyle()
                #if os(iOS)
                .frame(minHeight: LayoutDimensions.minTouchTarget)
                #endif

                Button("Manage subscriptions") {
                    showSubscriptions = true
                }
                .buttonStyle(.plain)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)
                #if os(iOS)
                .frame(minHeight: LayoutDimensions.minTouchTarget)
                #endif
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.top, Spacing.xxxl)
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

        VStack(alignment: .leading, spacing: Spacing.xs) {
            if showsHeader {
                HStack(spacing: Spacing.sm) {
                    Text(group.source.title ?? group.source.domain)
                        .sectionHeaderStyle()
                    if group.unread > 0 {
                        Text("\(group.unread)")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                            .monospacedDigit()
                    }

                    Spacer(minLength: Spacing.sm)

                    // Collapse sits in the header: after expanding a long
                    // history you're at the top, so the way back is right
                    // there. Expand lives at the bottom of the rows instead,
                    // where the hidden articles actually are.
                    if isCollapsible && isExpanded {
                        HistoryToggle(count: group.issues.count, isExpanded: true) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                _ = expandedSourceIDs.remove(group.id)
                            }
                        }
                    }
                }
                .padding(.bottom, Spacing.xs)
            }

            // Flat rows with hairline dividers, matching the library list.
            VStack(spacing: 0) {
                ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, issue in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 30)
                    }
                    issueRow(issue)
                }

                if isCollapsible && !isExpanded {
                    Divider()
                        .padding(.leading, 30)
                    HistoryToggle(count: group.issues.count, isExpanded: false, alignedToRows: true) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            _ = expandedSourceIDs.insert(group.id)
                        }
                    }
                }
            }
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

    /// Hide an issue from newsletter history.
    private func hide(_ item: Item) {
        withAnimation(.easeOut(duration: 0.25)) {
            item.status = .dismissed
            item.metadata["suggestionDismissed"] = "true"
            item.updatedAt = .now
            try? modelContext.save()
        }
    }
}

// MARK: - History Toggle

/// Expand/collapse control for a source's full history. Collapsed it reads
/// "18+ articles" at the bottom of the visible rows (where the hidden
/// articles are); expanded it reads "collapse −" in the section header
/// (where you are after expanding). Ink darkens on hover so it registers
/// as a button despite the quiet mono styling.
private struct HistoryToggle: View {
    let count: Int
    let isExpanded: Bool
    /// Bottom-of-list placement: indented to the title column and
    /// full-width so the whole line is clickable.
    var alignedToRows: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if isExpanded {
                    Text("collapse")
                } else {
                    Text("\(count)+")
                        .monospacedDigit()
                    Text("articles")
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .font(.groveMeta)
            .foregroundStyle(isHovering ? Color.textPrimary : Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isHovering ? Color.borderPrimary : Color.borderTag, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, alignedToRows ? 30 : 0)
        .padding(.vertical, alignedToRows ? Spacing.sm : Spacing.xs)
        .onHover { isHovering = $0 }
        .help(isExpanded ? "Show fewer articles" : "Show all \(count) articles")
        .accessibilityLabel(isExpanded ? "Show fewer articles" : "Show all \(count) articles")
        #if os(iOS)
        .frame(minHeight: LayoutDimensions.minTouchTarget)
        #endif
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
        HStack(spacing: 10) {
            // Same gutter as LibraryRowView: type icon, 20pt column. Unread
            // reads through ink weight on the title, not a separate marker.
            Image(systemName: item.type.iconName)
                .font(.groveMeta)
                .foregroundStyle(isUnread ? Color.textSecondary : Color.textMuted)
                .frame(width: 20)

            Text(item.title)
                .font(isUnread ? .groveBodyMedium : .groveBody)
                // Ink darkens on hover; layout never moves.
                .foregroundStyle(isUnread || isHovering ? Color.textPrimary : Color.textSecondary)
                .lineLimit(1)

            Spacer(minLength: Spacing.sm)

            #if os(macOS)
            // Always present at fixed size so revealing them never shifts
            // the row — they fade in rather than push in.
            HStack(spacing: Spacing.sm) {
                if !isKept {
                    Button("Keep") {
                        onKeep()
                    }
                    .font(.groveBadge)
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
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .accessibilityHidden(!isHovering)
            #endif

            if isKept {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityLabel("In library")
            }

            Text(publishedAt.relativeShort)
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isHovering)
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
