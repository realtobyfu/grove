import SwiftUI
import SwiftData

struct ItemReaderHeaderView: View {
    @Bindable var vm: ItemReaderViewModel
    /// Runs the export directly — there is no interstitial sheet.
    var onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: vm.item.type.iconName)
                    .foregroundStyle(Color.textSecondary)
                Text(vm.item.type.rawValue.capitalized)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)

                if vm.item.metadata["isAIGenerated"] == "true" {
                    AIMetaLabel(text: "AI-Generated Synthesis")
                }

                Spacer()

                #if os(macOS)
                // Export runs through NSSavePanel; on iPad the panel does not
                // exist, so rather than a dead button the control is absent.
                Button {
                    onExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.groveMeta)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                #endif

                if vm.item.type == .note || (vm.item.type == .article && vm.item.metadata["hasLLMOverview"] == "true") {
                    Button {
                        vm.toggleContentEditing()
                    } label: {
                        Label(vm.isEditingContent ? "Done" : "Edit", systemImage: vm.isEditingContent ? "checkmark" : "pencil")
                            .font(.groveMeta)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Text(vm.item.title)
                .font(.custom("Newsreader", size: 18))
                .fontWeight(.medium)
                .tracking(-0.36)
                .textSelection(.enabled)

            if vm.item.metadata["isAIGenerated"] == "true" {
                let isEdited = vm.item.metadata["isAIEdited"] == "true"
                AIMetaLabel(
                    text: isEdited ? "Edited" : "AI Draft",
                    systemImage: isEdited ? "pencil" : "sparkles"
                )
            } else if vm.item.metadata["hasLLMOverview"] == "true"
                        || vm.item.metadata["summaryGeneratedByAI"] == "true" {
                // Revert lives on the overview paragraph it actually reverts.
                AIMetaLabel(text: "AI-assisted")
            }

            // One-line summary display/edit
            if let summary = vm.item.metadata["summary"], !summary.isEmpty {
                ItemReaderSummaryField(vm: vm, summary: summary)
            }

            if let sourceURL = vm.item.sourceURL, !sourceURL.isEmpty {
                sourceURLView(sourceURL: sourceURL)
            }

            HStack(spacing: 16) {
                Label(vm.item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
                Label("\(vm.item.reflections.count) reflections", systemImage: "text.alignleft")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)

                if let readTime = vm.item.metadata["readTimeMinutes"], !readTime.isEmpty {
                    Label("\(readTime) min read", systemImage: "clock")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()
            }
        }
        .padding()
    }

    // MARK: - Source URL View

    @ViewBuilder
    private func sourceURLView(sourceURL: String) -> some View {
        if vm.item.metadata["videoLocalFile"] == "true", let path = vm.item.metadata["originalPath"] {
            HStack(spacing: 4) {
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
                HStack(spacing: 4) {
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
                HStack(spacing: 4) {
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
                HStack(spacing: 4) {
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
        HStack(spacing: 4) {
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

// MARK: - Overview Header

/// Kicker above the AI overview paragraph, plus the ghost "Revert to original"
/// link for the text it actually reverts. The link fades in on row hover.
struct AIOverviewHeaderRow: View {
    @Bindable var vm: ItemReaderViewModel

    @State private var isHovered = false
    @State private var isLinkHovered = false

    private var canRevert: Bool {
        vm.item.metadata["hasLLMOverview"] == "true"
            && !(vm.item.metadata["originalDescription"] ?? "").isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            AIMetaLabel(text: "AI Overview")

            if canRevert {
                Button {
                    vm.item.metadata["overviewFeedback"] = "reverted"
                    vm.revertOverview()
                } label: {
                    Text("Revert to original")
                        .font(.groveMeta)
                        .foregroundStyle(isLinkHovered ? Color.textPrimary : Color.textTertiary)
                        .underline(isLinkHovered)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Replace the AI overview with the original text")
                .opacity(isHovered || isLinkHovered ? 1 : restingOpacity)
                .onHover { isLinkHovered = $0 }
            }

            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered || isLinkHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    /// Pointer platforms reveal the link on hover; touch keeps it visible.
    private var restingOpacity: Double {
        #if os(macOS)
        // Faint but present: a fully invisible control is undiscoverable to
        // mouse users who never happen to hover the paragraph.
        return 0.35
        #else
        return 1
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
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
                        .font(.groveBodySecondary)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
                HStack(spacing: 6) {
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
