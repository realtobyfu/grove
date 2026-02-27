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
                    .font(.groveTitleLarge)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(allTags.count) tags")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)

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

            TagCloudView(
                allTags: allTags,
                groupedTags: groupedTags,
                mergeSuggestions: mergeSuggestions,
                showMergeSuggestions: showMergeSuggestions,
                isCreatingTag: $isCreatingTag,
                newTagName: $newTagName,
                newTagCategory: $newTagCategory,
                showMergeSuggestionsSheet: $showMergeSuggestions,
                onSelectTag: { tag in selectedTag = tag },
                onCreateTag: createTag
            )
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
