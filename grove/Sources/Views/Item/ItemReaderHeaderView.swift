import SwiftUI
import SwiftData

struct ItemReaderHeaderView: View {
    @Bindable var vm: ItemReaderViewModel
    @Binding var showItemExportSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: vm.item.type.iconName)
                    .foregroundStyle(Color.textSecondary)
                Text(vm.item.type.rawValue.capitalized)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)

                if vm.item.metadata["isAIGenerated"] == "true" {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text("AI-Generated Synthesis")
                            .font(.groveBadge)
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentBadge)
                    .clipShape(Capsule())
                }

                Spacer()

                Button {
                    showItemExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.groveMeta)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

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
                HStack(spacing: 4) {
                    Image(systemName: vm.item.metadata["isAIEdited"] == "true" ? "pencil" : "sparkles")
                        .font(.system(size: 9))
                    Text(vm.item.metadata["isAIEdited"] == "true" ? "Edited" : "AI Draft")
                        .font(.groveBadge)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentBadge)
                .clipShape(Capsule())
            }

            // Review banner (shown when LLM summary/overview is pending review)
            if vm.item.metadata["summaryReviewPending"] == "true" || vm.item.metadata["overviewReviewPending"] == "true" {
                ItemReaderReviewBanner(vm: vm)
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

                Spacer()

                HStack(spacing: 4) {
                    GrowthStageIndicator(stage: vm.item.growthStage, showLabel: true)
                    Text("\u{00B7}")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                    Text("\(vm.item.depthScore) pts")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
                .help(vm.scoreBreakdownTooltip)
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
        } else if vm.articleURL != nil {
            // Article URL -- clicking opens the in-app WebView reader
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

// MARK: - Review Banner

struct ItemReaderReviewBanner: View {
    @Bindable var vm: ItemReaderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                Text("AI-generated summary ready for review")
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textSecondary)
            }

            if let summary = vm.item.metadata["summary"], !summary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                        TextField("One-line summary", text: Binding(
                            get: { vm.item.metadata["summary"] ?? "" },
                            set: { vm.item.metadata["summary"] = $0 }
                        ))
                        .font(.groveBodySecondary)
                        .textFieldStyle(.plain)
                    }
                }
            }

            if vm.item.metadata["hasLLMOverview"] == "true" {
                Text("AI overview is shown below -- you can edit it with the Edit button.")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 8) {
                Button {
                    vm.acceptReview()
                } label: {
                    Label("Accept", systemImage: "checkmark")
                        .font(.groveBodySecondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if vm.item.metadata["overviewReviewPending"] == "true",
                   let original = vm.item.metadata["originalDescription"], !original.isEmpty {
                    Button {
                        vm.revertOverview()
                    } label: {
                        Label("Revert Overview", systemImage: "arrow.uturn.backward")
                            .font(.groveBodySecondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    vm.dismissReview()
                } label: {
                    Text("Dismiss")
                        .font(.groveBodySecondary)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    Color.borderTagDashed,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
    }
}
