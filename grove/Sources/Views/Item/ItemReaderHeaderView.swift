import SwiftUI
import SwiftData

struct ItemReaderHeaderView: View {
    @Bindable var vm: ItemReaderViewModel
    /// Runs the export directly — there is no interstitial sheet.
    var onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: vm.item.type.iconName)
                    .foregroundStyle(Color.textSecondary)
                Text(vm.item.type.displayName)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                #if os(macOS)
                // Export runs through NSSavePanel; on iPad the panel does not
                // exist, so rather than a dead button the control is absent.
                Button {
                    onExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.grove(.secondary, size: .compact))
                #endif

                if vm.canEditContent {
                    Button {
                        vm.toggleContentEditing()
                    } label: {
                        Label(vm.isEditingContent ? "Done" : "Edit", systemImage: vm.isEditingContent ? "checkmark" : "pencil")
                    }
                    .buttonStyle(.grove(.secondary, size: .compact))
                }
            }

            Text(vm.item.title)
                .font(.groveItemTitle)
                .tracking(-0.36)
                .textSelection(.enabled)

            if vm.item.hasLLMOverview || vm.item.isSummaryGeneratedByAI {
                AIMetaLabel(text: "AI-assisted")
            }

            // One-line summary display/edit
            if let summary = vm.item.summary, !summary.isEmpty {
                ItemReaderSummaryField(vm: vm, summary: summary)
            }

            if let sourceURL = vm.item.sourceURL, !sourceURL.isEmpty {
                sourceURLView(sourceURL: sourceURL)
            }

            HStack(spacing: Spacing.lg) {
                Label(vm.item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                Label("\(vm.item.reflections.count) reflections", systemImage: "text.alignleft")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)

                if let readTime = vm.item.readTimeMinutes {
                    Label("\(readTime) min read", systemImage: "clock")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()
            }

            if let overview = vm.item.overview, !overview.isEmpty {
                ItemCollapsibleTextBlock(
                    label: "AI Overview",
                    text: overview,
                    onSelectText: { vm.webSelectedText = $0 }
                )
                .id(vm.item.id)
            }

            // Only on an item whose edited content kept the overview's place;
            // this is what that content replaced.
            if vm.item.hasLLMOverview, let original = vm.item.originalDescription, !original.isEmpty {
                ItemCollapsibleTextBlock(
                    label: "Original Description",
                    systemImage: nil,
                    text: original,
                    startsExpanded: false,
                    onSelectText: { vm.webSelectedText = $0 }
                )
                .id(vm.item.id)
            }
        }
        .padding()
    }

    // MARK: - Source URL View

    @ViewBuilder
    private func sourceURLView(sourceURL: String) -> some View {
        if vm.item.isVideoLocalFile, let path = vm.item.originalPath {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder")
                    .font(.groveMeta)
                Text(path)
                    .font(.groveMeta)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .foregroundStyle(Color.textSecondary)
        } else if vm.isPDFItem {
            // The document opens in the PDF pane, never the browser — this is
            // the way back in once the reader has stepped out to the overview.
            Button {
                withAnimation(.easeOut(duration: 0.2)) { vm.showPDFReader = true }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "doc.richtext")
                        .font(.groveMeta)
                    Text(sourceURL)
                        .font(.groveMeta)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Read in App")
        } else if vm.readerWebURL != nil {
            // Article URL (or a remote video's embed) -- clicking opens the
            // in-app WebView reader
            Button {
                withAnimation(.easeOut(duration: 0.2)) { vm.showArticleWebView = true }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.groveMeta)
                    Text(sourceURL)
                        .font(.groveMeta)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Read in App")
        } else {
            Link(destination: URL(string: sourceURL) ?? URL(string: "about:blank")!) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "link")
                        .font(.groveMeta)
                    Text(sourceURL)
                        .font(.groveMeta)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(Color.textSecondary)
            }
        }
    }
}

// MARK: - AI Meta Label

/// Bare mono-caps status line — no capsule, no fill. Hierarchy comes from the
/// mono face and tracking, like the header's other meta rows.
struct AIMetaLabel: View {
    let text: String
    var systemImage: String? = "sparkles"

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9))
            }
            Text(text.uppercased())
                .font(.groveBadge)
                .tracking(0.6)
        }
        .foregroundStyle(Color.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Collapsible Text Block

/// Text that sits beside an item's content rather than in it, under a meta
/// label that collapses it. Whether it is open lives here and nowhere else.
struct ItemCollapsibleTextBlock: View {
    let label: String
    let systemImage: String?
    let text: String
    let onSelectText: ((String?) -> Void)?

    @State private var isExpanded: Bool

    init(
        label: String,
        systemImage: String? = "sparkles",
        text: String,
        startsExpanded: Bool = true,
        onSelectText: ((String?) -> Void)? = nil
    ) {
        self.label = label
        self.systemImage = systemImage
        self.text = text
        self.onSelectText = onSelectText
        _isExpanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    AIMetaLabel(text: label, systemImage: systemImage)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Spacer(minLength: 0)
                }
                .frame(minHeight: minimumRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                SelectableMarkdownView(markdown: text, onSelectText: onSelectText)
            }
        }
        .padding(.top, Spacing.xs)
    }

    /// Touch needs the full target; a pointer doesn't.
    private var minimumRowHeight: CGFloat {
        #if os(iOS)
        LayoutDimensions.minTouchTarget
        #else
        0
        #endif
    }
}

// MARK: - Summary Field

struct ItemReaderSummaryField: View {
    @Bindable var vm: ItemReaderViewModel
    let summary: String

    var body: some View {
        Group {
            if vm.isEditingSummary {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xsm) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                        TextField("One-line summary", text: Binding(
                            get: { vm.editableSummary },
                            set: { vm.editableSummary = $0 }
                        ))
                        .font(.groveBodySecondary)
                        .textFieldStyle(.plain)
                    }
                    HStack {
                        Text("\(vm.editableSummary.count)/120")
                            .font(.groveMeta)
                            .foregroundStyle(vm.editableSummary.count > 120 ? Color.textPrimary : Color.textTertiary)
                        Spacer()
                        Button("Done") {
                            vm.finishEditingSummary()
                        }
                        .buttonStyle(.grove(.secondary, size: .compact))
                    }
                }
            } else {
                HStack(spacing: Spacing.xsm) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Text(summary)
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        vm.beginEditingSummary(currentSummary: summary)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Edit summary")
                }
            }
        }
    }
}
