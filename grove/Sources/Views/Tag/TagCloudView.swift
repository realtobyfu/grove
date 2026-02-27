import SwiftUI

/// Extracted from TagBrowserView — tag cloud / tag list display with category sections,
/// tag pills with children, new tag form, and merge suggestion banner.
struct TagCloudView: View {
    let allTags: [Tag]
    let groupedTags: [(TagCategory, [Tag])]
    let mergeSuggestions: [TagMergeSuggestion]
    let showMergeSuggestions: Bool

    @Binding var isCreatingTag: Bool
    @Binding var newTagName: String
    @Binding var newTagCategory: TagCategory
    @Binding var showMergeSuggestionsSheet: Bool

    let onSelectTag: (Tag) -> Void
    let onCreateTag: () -> Void

    var body: some View {
        if allTags.isEmpty {
            emptyState
        } else {
            tagList
        }
    }

    // MARK: - Tag List

    private var tagList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // New tag creation inline
                if isCreatingTag {
                    newTagForm
                }

                // Merge suggestions banner
                if !mergeSuggestions.isEmpty && !showMergeSuggestions {
                    mergeBanner
                }

                ForEach(groupedTags, id: \.0) { category, tags in
                    tagCategorySection(category: category, tags: tags)
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)
            Text("No Tags Yet")
                .font(.groveTitleLarge)
                .fontWeight(.semibold)
            Text("Tags help organize your items. Add tags to items from the inspector, or create one here.")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if !isCreatingTag {
                Button("Create a Tag") {
                    isCreatingTag = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                newTagForm
                    .frame(maxWidth: 300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - New Tag Form

    private var newTagForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Tag")
                .sectionHeaderStyle()

            HStack(spacing: 8) {
                TextField("Tag name", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onCreateTag() }

                Picker("", selection: $newTagCategory) {
                    ForEach(TagCategory.allCases, id: \.self) { cat in
                        Text(cat.displayName).tag(cat)
                    }
                }
                .frame(width: 120)

                Button("Add") { onCreateTag() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Cancel") {
                    newTagName = ""
                    isCreatingTag = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Merge Banner

    private var mergeBanner: some View {
        Button {
            showMergeSuggestionsSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(Color.textPrimary)
                    .fontWeight(.semibold)
                Text("\(mergeSuggestions.count) merge suggestion\(mergeSuggestions.count == 1 ? "" : "s") found")
                    .font(.groveBodySmall)
                Spacer()
                Text("Review")
                    .font(.groveBodySmall)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(10)
            .background(Color.accentBadge)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Section

    private func tagCategorySection(category: TagCategory, tags: [Tag]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.groveMeta)
                    .foregroundStyle(category.color)
                Text(category.displayName)
                    .sectionHeaderStyle()
                Text("\(tags.count)")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textTertiary)
            }

            FlowLayout(spacing: 6) {
                ForEach(tags) { tag in
                    tagPillWithChildren(tag: tag)
                }
            }
        }
    }

    // MARK: - Tag Pill with Children

    @ViewBuilder
    private func tagPillWithChildren(tag: Tag) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TagPillView(tag: tag, showTrend: true) {
                onSelectTag(tag)
            }

            // Show indented children if any
            if !tag.childTags.isEmpty {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.borderPrimary)
                        .frame(width: 1)
                        .padding(.leading, 10)
                    FlowLayout(spacing: 4) {
                        ForEach(tag.childTags.sorted(by: { $0.name < $1.name })) { child in
                            TagPillView(tag: child, showTrend: true, isChild: true) {
                                onSelectTag(child)
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }
}
