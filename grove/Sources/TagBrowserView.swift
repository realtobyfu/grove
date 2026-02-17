import SwiftUI
import SwiftData

struct TagBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Binding var selectedItem: Item?

    @State private var selectedTag: Tag?
    @State private var isCreatingTag = false
    @State private var newTagName = ""
    @State private var newTagCategory: TagCategory = .custom
    @State private var showMergeSuggestions = false
    @State private var showHierarchySuggestions = false
    @State private var mergeSuggestions: [TagMergeSuggestion] = []
    @State private var hierarchySuggestions: [TagHierarchySuggestion] = []

    private var tagService: TagService {
        TagService(modelContext: modelContext)
    }

    private var groupedTags: [(TagCategory, [Tag])] {
        // Only show root-level tags (no parent) at top level
        let rootTags = allTags.filter { $0.parentTag == nil }
        let grouped = Dictionary(grouping: rootTags, by: \.category)
        return TagCategory.allCases.compactMap { category in
            guard let tags = grouped[category], !tags.isEmpty else { return nil }
            return (category, tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    var body: some View {
        if let tag = selectedTag {
            TagDetailView(tag: tag, selectedItem: $selectedItem, onBack: { selectedTag = nil })
        } else {
            tagBrowserList
        }
    }

    private var tagBrowserList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tags")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(allTags.count) tags")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Menu {
                    Button {
                        refreshSuggestions()
                        showMergeSuggestions = true
                    } label: {
                        Label("Merge Suggestions", systemImage: "arrow.triangle.merge")
                    }
                    Button {
                        refreshHierarchy()
                        showHierarchySuggestions = true
                    } label: {
                        Label("Hierarchy Suggestions", systemImage: "list.triangle")
                    }
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .help("Tag Analysis")

                Button {
                    isCreatingTag.toggle()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create Tag")
            }
            .padding()

            Divider()

            if allTags.isEmpty {
                emptyState
            } else {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            tagService.updateTrends(for: allTags)
            mergeSuggestions = tagService.findMergeSuggestions(from: allTags)
        }
        .sheet(isPresented: $showMergeSuggestions) {
            TagMergeSuggestionsView(
                suggestions: mergeSuggestions,
                onMerge: { keep, remove in
                    tagService.mergeTags(keep: keep, remove: remove)
                    mergeSuggestions = tagService.findMergeSuggestions(from: allTags)
                },
                onDismissAll: {
                    mergeSuggestions = []
                    showMergeSuggestions = false
                }
            )
        }
        .sheet(isPresented: $showHierarchySuggestions) {
            TagHierarchySuggestionsView(
                suggestions: hierarchySuggestions,
                onApply: { parent, child in
                    tagService.applyHierarchy(parent: parent, child: child)
                    hierarchySuggestions = tagService.findHierarchySuggestions(from: allTags)
                },
                onDismissAll: {
                    hierarchySuggestions = []
                    showHierarchySuggestions = false
                }
            )
        }
    }

    private var mergeBanner: some View {
        Button {
            showMergeSuggestions = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(.orange)
                Text("\(mergeSuggestions.count) merge suggestion\(mergeSuggestions.count == 1 ? "" : "s") found")
                    .font(.caption)
                Spacer()
                Text("Review")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(10)
            .background(.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.orange.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Tags Yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Tags help organize your items. Add tags to items from the inspector, or create one here.")
                .font(.body)
                .foregroundStyle(.secondary)
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

    private var newTagForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Tag")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Tag name", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createTag() }

                Picker("", selection: $newTagCategory) {
                    ForEach(TagCategory.allCases, id: \.self) { cat in
                        Text(cat.displayName).tag(cat)
                    }
                }
                .frame(width: 120)

                Button("Add") { createTag() }
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
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tagCategorySection(category: TagCategory, tags: [Tag]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.caption)
                    .foregroundStyle(category.color)
                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(tags.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            FlowLayout(spacing: 6) {
                ForEach(tags) { tag in
                    tagPillWithChildren(tag: tag)
                }
            }
        }
    }

    @ViewBuilder
    private func tagPillWithChildren(tag: Tag) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TagPillView(tag: tag, showTrend: true) {
                selectedTag = tag
            }

            // Show indented children if any
            if !tag.childTags.isEmpty {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1)
                        .padding(.leading, 10)
                    FlowLayout(spacing: 4) {
                        ForEach(tag.childTags.sorted(by: { $0.name < $1.name })) { child in
                            TagPillView(tag: child, showTrend: true, isChild: true) {
                                selectedTag = child
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }

    private func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        // Prevent duplicates (case-insensitive)
        if allTags.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            return
        }

        let tag = Tag(name: name, category: newTagCategory)
        modelContext.insert(tag)
        newTagName = ""
        isCreatingTag = false
    }

    private func refreshSuggestions() {
        mergeSuggestions = tagService.findMergeSuggestions(from: allTags)
    }

    private func refreshHierarchy() {
        hierarchySuggestions = tagService.findHierarchySuggestions(from: allTags)
    }
}

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
                    .font(isChild ? .caption2 : .caption)
                // Usage count
                Text("\(tag.items.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
                .foregroundStyle(.green)
        case .decreasing:
            Image(systemName: "arrow.down.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.red)
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
                    .font(.headline)
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
                        .foregroundStyle(.green)
                    Text("No Duplicates Found")
                        .font(.headline)
                    Text("All tags look unique.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                tagLabel(suggestion.tag2)
                Spacer()
                Text("\(Int(suggestion.similarity * 100))% similar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(.secondary)

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
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tagLabel(_ tag: Tag) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.category.color)
                .frame(width: 6, height: 6)
            Text(tag.name)
                .font(.caption)
                .fontWeight(.medium)
            Text("(\(tag.items.count))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
                    .font(.headline)
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
                        .foregroundStyle(.secondary)
                    Text("No Hierarchy Detected")
                        .font(.headline)
                    Text("No parent-child relationships found among current tags.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(suggestion.parentTag.category.color.opacity(0.12))
                .clipShape(Capsule())

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(suggestion.childTag.category.color)
                        .frame(width: 5, height: 5)
                    Text(suggestion.childTag.name)
                        .font(.caption)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(suggestion.childTag.category.color.opacity(0.08))
                .clipShape(Capsule())

                Spacer()
            }

            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Set \"\(suggestion.parentTag.name)\" as parent of \"\(suggestion.childTag.name)\"") {
                onApply(suggestion.parentTag, suggestion.childTag)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
