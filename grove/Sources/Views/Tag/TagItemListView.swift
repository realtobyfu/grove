import SwiftUI

/// Extracted from TagBrowserView — tag pill view, merge suggestions sheet, and hierarchy suggestions sheet.

// MARK: - Tag Pill View (browsable, colored by category, with usage count and trend)

struct TagPillView: View {
    let tag: Tag
    var showTrend: Bool = false
    var isChild: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Circle()
                    .fill(tag.category.color)
                    .frame(width: isChild ? 5 : 6, height: isChild ? 5 : 6)
                Text(tag.name)
                    .font(isChild ? .groveBadge : .groveBodySmall)
                // Usage count
                Text("\(tag.items.count)")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textTertiary)
                // Trend indicator
                if showTrend {
                    trendIcon
                }
            }
            .padding(.horizontal, isChild ? 6 : 8)
            .padding(.vertical, isChild ? 3 : 5)
            .background(tag.category.color.opacity(isChild ? 0.08 : 0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trendIcon: some View {
        switch tag.trend {
        case .increasing:
            Image(systemName: "arrow.up.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .fontWeight(.medium)
        case .decreasing:
            Image(systemName: "arrow.down.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .fontWeight(.semibold)
        case .stable:
            EmptyView()
        }
    }
}

// MARK: - Merge Suggestions Sheet

struct TagMergeSuggestionsView: View {
    let suggestions: [TagMergeSuggestion]
    let onMerge: (Tag, Tag) -> Void
    let onDismissAll: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Merge Suggestions")
                    .font(.groveItemTitle)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding()

            Divider()

            if suggestions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.textPrimary)
                        .fontWeight(.medium)
                    Text("No Duplicates Found")
                        .font(.groveItemTitle)
                    Text("All tags look unique.")
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(suggestions) { suggestion in
                            MergeSuggestionRow(
                                suggestion: suggestion,
                                onMerge: onMerge
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 480, height: 400)
    }
}

struct MergeSuggestionRow: View {
    let suggestion: TagMergeSuggestion
    let onMerge: (Tag, Tag) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                tagLabel(suggestion.tag1)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                tagLabel(suggestion.tag2)
                Spacer()
                Text("\(Int(suggestion.similarity * 100))% similar")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)
            }

            Text(suggestion.reason)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 8) {
                Button("Keep \"\(suggestion.tag1.name)\"") {
                    onMerge(suggestion.tag1, suggestion.tag2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Keep \"\(suggestion.tag2.name)\"") {
                    onMerge(suggestion.tag2, suggestion.tag1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tagLabel(_ tag: Tag) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.category.color)
                .frame(width: 6, height: 6)
            Text(tag.name)
                .font(.groveBodySmall)
                .fontWeight(.medium)
            Text("(\(tag.items.count))")
                .font(.groveBadge)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tag.category.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Hierarchy Suggestions Sheet

struct TagHierarchySuggestionsView: View {
    let suggestions: [TagHierarchySuggestion]
    let onApply: (Tag, Tag) -> Void
    let onDismissAll: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hierarchy Suggestions")
                    .font(.groveItemTitle)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding()

            Divider()

            if suggestions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.textSecondary)
                    Text("No Hierarchy Detected")
                        .font(.groveItemTitle)
                    Text("No parent-child relationships found among current tags.")
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(suggestions) { suggestion in
                            HierarchySuggestionRow(
                                suggestion: suggestion,
                                onApply: onApply
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 480, height: 400)
    }
}

struct HierarchySuggestionRow: View {
    let suggestion: TagHierarchySuggestion
    let onApply: (Tag, Tag) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(suggestion.parentTag.category.color)
                        .frame(width: 6, height: 6)
                    Text(suggestion.parentTag.name)
                        .font(.groveBodySmall)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(suggestion.parentTag.category.color.opacity(0.12))
                .clipShape(Capsule())

                Image(systemName: "arrow.right")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(suggestion.childTag.category.color)
                        .frame(width: 5, height: 5)
                    Text(suggestion.childTag.name)
                        .font(.groveBodySmall)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(suggestion.childTag.category.color.opacity(0.08))
                .clipShape(Capsule())

                Spacer()
            }

            Text(suggestion.reason)
                .font(.groveBodySmall)
                .foregroundStyle(Color.textSecondary)

            Button("Set \"\(suggestion.parentTag.name)\" as parent of \"\(suggestion.childTag.name)\"") {
                onApply(suggestion.parentTag, suggestion.childTag)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
