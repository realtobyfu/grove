import SwiftUI
import SwiftData

struct TagDetailView: View {
    @Bindable var tag: Tag
    @Binding var selectedItem: Item?
    var onBack: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isEditingCategory = false
    @State private var showDeleteConfirmation = false
    @State private var sortOrder: TagItemSort = .dateAdded
    @State private var showSynthesisSheet = false

    enum TagItemSort: String, CaseIterable {
        case dateAdded = "Date Added"
        case title = "Title"

        var comparator: (Item, Item) -> Bool {
            switch self {
            case .dateAdded: return { $0.createdAt > $1.createdAt }
            case .title: return { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            }
        }
    }

    private var sortedItems: [Item] {
        tag.items.sorted(by: sortOrder.comparator)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if tag.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSynthesisSheet) {
            SynthesisSheet(
                items: tag.items,
                scopeTitle: "Tag: \(tag.name)",
                board: nil,
                onCreated: { item in
                    selectedItem = item
                }
            )
        }
        .alert("Delete Tag", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteTag()
            }
        } message: {
            Text("Are you sure you want to delete \"\(tag.name)\"? It will be removed from all items.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Back button
            HStack {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                        Text("All Tags")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                // Sort picker
                Picker("Sort", selection: $sortOrder) {
                    ForEach(TagItemSort.allCases, id: \.self) { sort in
                        Text(sort.rawValue).tag(sort)
                    }
                }
                .frame(width: 130)

                Button {
                    showSynthesisSheet = true
                } label: {
                    Label("Synthesize", systemImage: "sparkles")
                }
                .help("Generate AI synthesis from items with this tag")
                .disabled(tag.items.count < 2)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete Tag")
            }

            // Tag info
            HStack(spacing: 8) {
                Circle()
                    .fill(tag.category.color)
                    .frame(width: 10, height: 10)

                Text(tag.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                // Category picker
                Picker("", selection: $tag.category) {
                    ForEach(TagCategory.allCases, id: \.self) { cat in
                        Label(cat.displayName, systemImage: cat.iconName).tag(cat)
                    }
                }
                .frame(width: 140)

                Spacer()

                Text("\(tag.items.count) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No items with this tag")
                .font(.headline)
            Text("Tag items from the inspector panel to see them here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(sortedItems) { item in
                    TagItemRow(item: item, isSelected: selectedItem?.id == item.id) {
                        selectedItem = item
                    } onRemoveTag: {
                        removeTagFromItem(item)
                    }
                }
            }
            .padding()
        }
    }

    private func removeTagFromItem(_ item: Item) {
        item.tags.removeAll { $0.id == tag.id }
        item.updatedAt = .now
    }

    private func deleteTag() {
        // Remove tag from all items first
        for item in tag.items {
            item.tags.removeAll { $0.id == tag.id }
            item.updatedAt = .now
        }
        modelContext.delete(tag)
        onBack()
    }
}

// MARK: - Tag Item Row

struct TagItemRow: View {
    let item: Item
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemoveTag: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: item.type.iconName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(item.type.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if !item.tags.isEmpty {
                            HStack(spacing: 3) {
                                ForEach(item.tags.prefix(3)) { tag in
                                    Text(tag.name)
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(tag.category.color.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                if item.tags.count > 3 {
                                    Text("+\(item.tags.count - 3)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Remove tag button
                Button {
                    onRemoveTag()
                } label: {
                    Image(systemName: "tag.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove tag from this item")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
