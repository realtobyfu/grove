import SwiftUI
import SwiftData

/// Manages newsletter/RSS subscriptions: existing FeedSources, feeds
/// discovered from the user's library (suggestions), manual feed adds,
/// and an entry point into the curated newsletter directory.
///
/// Presented three ways: as a sheet from the newsletter inbox (`showsHeader`
/// true, so it carries its own title bar and close button), as a macOS
/// Settings tab, and pushed onto the iOS settings stack.
struct SubscriptionsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FeedSource.createdAt, order: .reverse) private var allSources: [FeedSource]

    /// True when the view supplies its own title bar and close button —
    /// i.e. presented as a sheet rather than inside a settings container.
    var showsHeader: Bool = false

    @State private var newFeedURL = ""
    @State private var isValidatingFeed = false
    @State private var addFeedError: String?
    @State private var showDirectory = false

    /// Sources the user owns: manually added or explicitly subscribed. Keyed on
    /// the explicit isUserSubscribed flag so disabling a feed doesn't move it.
    private var subscriptions: [FeedSource] {
        allSources.filter { $0.isUserSubscribed || !$0.isAutoDiscovered }
    }

    /// Discovered-but-never-subscribed feeds, surfaced as quiet suggestions.
    private var suggestedSources: [FeedSource] {
        allSources.filter { $0.isAutoDiscovered && !$0.isUserSubscribed }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: LayoutDimensions.sectionSpacing) {
                    subscriptionsSection

                    if !suggestedSources.isEmpty {
                        suggestedSection
                    }

                    addFeedSection
                    directorySection
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.bgPrimary)
        .navigationTitle("Newsletters")
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
        .sheet(isPresented: $showDirectory) {
            NewsletterDirectoryView()
                #if os(macOS)
                .frame(width: 560, height: 640)
                #endif
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "newspaper")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
            Text("Newsletters")
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
            .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
            #endif
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close newsletters")
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Subscriptions

    private var subscriptionsSection: some View {
        section(
            title: "Subscriptions",
            trailing: subscriptions.isEmpty ? nil : "\(subscriptions.count)",
            footnote: subscriptions.isEmpty ? nil : "New issues from enabled feeds appear quietly in your inbox."
        ) {
            if subscriptions.isEmpty {
                emptySubscriptions
            } else {
                rowStack(subscriptions) { source in
                    FeedSubscriptionRow(source: source, onDelete: { delete(source) })
                }
            }
        }
    }

    private var emptySubscriptions: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("No subscriptions yet")
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)
            Text("Add a feed below, or browse the directory for something worth reading.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .cardStyle()
    }

    // MARK: - Suggested From Library

    private var suggestedSection: some View {
        section(
            title: "Suggested from your library",
            footnote: "Feeds found on sites you save from. Nothing is fetched unless you subscribe."
        ) {
            rowStack(suggestedSources) { source in
                HStack(spacing: Spacing.md) {
                    FeedMonogram(source: source)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title ?? source.domain)
                            .font(.groveBodyMedium)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(source.domain)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Spacing.sm)

                    Button("Subscribe") {
                        subscribe(source)
                    }
                    .buttonStyle(GroveCompactButtonStyle(prominent: true))

                    Button {
                        dismissSuggestion(source)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #if os(iOS)
                    .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                    #endif
                    .accessibilityLabel("Dismiss suggestion")
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    // MARK: - Add Feed

    private var addFeedSection: some View {
        section(title: "Add a feed") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "link")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)

                    TextField("https://example.com/feed", text: $newFeedURL)
                        .textFieldStyle(.plain)
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .onSubmit { addFeed() }
                        .onChange(of: newFeedURL) { _, _ in
                            addFeedError = nil
                        }

                    if isValidatingFeed {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Add") {
                            addFeed()
                        }
                        .buttonStyle(GroveCompactButtonStyle(prominent: true))
                        .disabled(trimmedFeedURL.isEmpty)
                        .opacity(trimmedFeedURL.isEmpty ? 0.4 : 1)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .cardStyle(background: .bgInput)

                if let addFeedError {
                    Label(addFeedError, systemImage: "exclamationmark.triangle")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var trimmedFeedURL: String {
        newFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Directory

    private var directorySection: some View {
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
                    Text("A hand-picked catalog, ranked by what you save.")
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
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
    }

    // MARK: - Section Scaffolding

    /// Section = tracked mono header, a card of content, and an optional footnote.
    private func section<Content: View>(
        title: String,
        trailing: String? = nil,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text(title)
                    .sectionHeaderStyle()
                if let trailing {
                    Text(trailing)
                        .font(.groveBadge)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            content()

            if let footnote {
                Text(footnote)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xs)
            }
        }
    }

    /// Divider-separated rows inside a single card container.
    private func rowStack<Item: Identifiable, Row: View>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .padding(.leading, Spacing.md)
                }
                row(item)
            }
        }
        .cardStyle()
    }

    // MARK: - Actions

    private func subscribe(_ source: FeedSource) {
        FeedSubscriptionService.subscribe(source, in: modelContext)
    }

    private func dismissSuggestion(_ source: FeedSource) {
        FeedPreferencesStore.dismissDiscovery(source.feedURL)
        modelContext.delete(source)
        try? modelContext.save()
    }

    private func delete(_ source: FeedSource) {
        // Remember the URL so discovery doesn't silently resurrect the feed.
        FeedPreferencesStore.dismissDiscovery(source.feedURL)
        modelContext.delete(source)
        try? modelContext.save()
    }

    private func addFeed() {
        let trimmed = trimmedFeedURL
        guard !trimmed.isEmpty else { return }

        isValidatingFeed = true
        addFeedError = nil

        Task {
            defer { isValidatingFeed = false }
            switch await FeedSubscriptionService.validateAndAdd(urlString: trimmed, in: modelContext) {
            case .success:
                newFeedURL = ""
            case .failure(let error):
                addFeedError = error.errorDescription
            }
        }
    }
}

// MARK: - Subscription Row

private struct FeedSubscriptionRow: View {
    @Bindable var source: FeedSource
    let onDelete: () -> Void

    @State private var isHovering = false

    private var statusText: String {
        if let lastFetched = source.lastFetchedAt {
            return "fetched \(lastFetched.formatted(.relative(presentation: .named)))"
        }
        return "not fetched yet"
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            FeedMonogram(source: source)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.title ?? source.domain)
                    .font(.groveBodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xs) {
                    Text(source.domain)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)

                    Text("·")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)

                    Text(statusText)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.sm)

            if source.errorCount > 0 {
                Label("\(source.errorCount)", systemImage: "exclamationmark.triangle")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)
                    .help("Recent fetch failures")
            }

            // Rows no longer live in a List, so swipe-to-delete is gone:
            // give removal an explicit control (revealed on hover on macOS).
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .opacity(isHovering ? 1 : 0)
            #else
            .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
            #endif
            .accessibilityLabel("Remove \(source.title ?? source.domain)")

            Toggle("", isOn: $source.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Color.textPrimary)
                .accessibilityLabel("Enable \(source.title ?? source.domain)")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .opacity(source.isEnabled ? 1 : 0.55)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Unsubscribe & Remove", systemImage: "trash")
            }
        }
    }
}

// MARK: - Monogram

/// Stands in for a feed icon: first letter of the feed's name, monochrome.
private struct FeedMonogram: View {
    let source: FeedSource

    private var letter: String {
        let name = source.title ?? source.domain
        return String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        Text(letter)
            .font(.groveBadge)
            .foregroundStyle(Color.textSecondary)
            .frame(width: 28, height: 28)
            .background(Color.bgTagActive)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}

// MARK: - Button Style

/// Small monochrome button used for the inline Add/Subscribe actions.
/// Same 4pt-radius language as other inline buttons (e.g. library Discuss).
private struct GroveCompactButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.groveBodySmall)
            .foregroundStyle(prominent ? Color.textInverse : Color.textPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs + 1)
            .background(prominent ? Color.textPrimary : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(prominent ? Color.clear : Color.borderPrimary, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
