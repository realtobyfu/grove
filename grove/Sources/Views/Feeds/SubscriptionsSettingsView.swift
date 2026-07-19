import SwiftUI
import SwiftData

/// Manages newsletter/RSS subscriptions: existing FeedSources, feeds
/// discovered from the user's library (suggestions), manual feed adds,
/// and an entry point into the curated newsletter directory.
struct SubscriptionsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FeedSource.createdAt, order: .reverse) private var allSources: [FeedSource]

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
        Form {
            subscriptionsSection

            if !suggestedSources.isEmpty {
                suggestedSection
            }

            addFeedSection
            directorySection
        }
        .formStyle(.grouped)
        .navigationTitle("Newsletters")
        #if os(macOS)
        .frame(minWidth: 400)
        #endif
        .sheet(isPresented: $showDirectory) {
            NewsletterDirectoryView()
                #if os(macOS)
                .frame(width: 560, height: 640)
                #endif
        }
    }

    // MARK: - Subscriptions

    private var subscriptionsSection: some View {
        Section("Subscriptions") {
            if subscriptions.isEmpty {
                Text("No subscriptions yet. Add a feed below or browse the directory.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(subscriptions) { source in
                    FeedSubscriptionRow(source: source, onDelete: { delete(source) })
                }
            }

            Text("New issues from enabled feeds appear quietly in your inbox.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Suggested From Library

    private var suggestedSection: some View {
        Section("Suggested from your library") {
            ForEach(suggestedSources) { source in
                HStack(spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title ?? source.domain)
                            .font(.groveBody)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(source.domain)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("Subscribe") {
                        subscribe(source)
                    }
                    .font(.groveBodySmall)
                    .buttonStyle(.bordered)

                    Button {
                        dismissSuggestion(source)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    #if os(iOS)
                    .frame(minWidth: 44, minHeight: 44)
                    #endif
                    .accessibilityLabel("Dismiss suggestion")
                }
            }

            Text("Feeds found on sites you save from. Nothing is fetched unless you subscribe.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Add Feed

    private var addFeedSection: some View {
        Section("Add a feed") {
            HStack(spacing: Spacing.sm) {
                TextField("https://example.com/feed", text: $newFeedURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.groveBody)
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
                    .font(.groveBodySmall)
                    .buttonStyle(.bordered)
                    .disabled(newFeedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let addFeedError {
                Text(addFeedError)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - Directory

    private var directorySection: some View {
        Section {
            Button {
                showDirectory = true
            } label: {
                Label("Browse directory", systemImage: "newspaper")
                    .font(.groveBody)
            }
            #if os(iOS)
            .frame(minHeight: 44)
            #endif

            Text("A hand-picked catalog of quality newsletters, ranked by what you save.")
                .font(.groveBodySmall)
                .foregroundStyle(Color.textTertiary)
        }
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
        let trimmed = newFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title ?? source.domain)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.sm) {
                    Text(source.domain)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)

                    if let lastFetched = source.lastFetchedAt {
                        Text("fetched \(lastFetched.formatted(.relative(presentation: .named)))")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        Text("not fetched yet")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Spacer()

            if source.errorCount > 0 {
                Label("\(source.errorCount)", systemImage: "exclamationmark.triangle")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)
                    .help("Recent fetch failures")
            }

            Toggle("", isOn: $source.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Enable \(source.title ?? source.domain)")
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Unsubscribe & Remove", systemImage: "trash")
            }
        }
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        #endif
    }
}
