import SwiftUI

/// Grid display mode for the library. Shows items as cards in an adaptive grid.
struct LibraryGridView: View {
    let displayedItems: [Item]
    let searchQuery: String
    let isMultiSelectMode: Bool
    let selectedIDs: Set<UUID>
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    let onToggleSelection: (Item) -> Void
    let onEnterMultiSelect: (Item) -> Void
    let onDeleteRequest: (Item) -> Void

    var body: some View {
        if displayedItems.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: Spacing.md)],
                    spacing: Spacing.md
                ) {
                    ForEach(displayedItems) { item in
                        gridCard(for: item)
                    }
                }
                .padding(Spacing.md)
                if isMultiSelectMode && !selectedIDs.isEmpty {
                    Spacer().frame(height: 52)
                }
            }
        }
    }

    // MARK: - Grid Card

    private func gridCard(for item: Item) -> some View {
        let isItemSelected = selectedIDs.contains(item.id)
        let isHighlighted = isMultiSelectMode ? isItemSelected : selectedItem?.id == item.id

        return Button {
            handleCardTap(item: item)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: item.type.iconName)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)

                    Spacer()

                    if isMultiSelectMode {
                        Image(systemName: isItemSelected ? "checkmark.circle.fill" : "circle")
                            .font(.groveBody)
                            .foregroundStyle(isItemSelected ? Color.textPrimary : Color.textMuted)
                    }
                }

                Text(item.title)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    if let firstBoard = item.boards.first {
                        Text(firstBoard.title)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        Text("Unfiled")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Text(item.updatedAt.relativeShort)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }

                HStack(spacing: Spacing.sm) {
                    GrowthStageIndicator(stage: item.growthStage)
                    let connectionCount = item.outgoingConnections.count + item.incomingConnections.count
                    if connectionCount > 0 {
                        Label("\(connectionCount)", systemImage: "link")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                    }
                    if item.reflections.count > 0 {
                        Label("\(item.reflections.count)", systemImage: "text.alignleft")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHighlighted ? Color.bgCard.opacity(0.85) : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHighlighted ? Color.borderInput : Color.borderPrimary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            rowContextMenu(for: item)
        }
    }

    private func handleCardTap(item: Item) {
        if isMultiSelectMode {
            withAnimation(.easeInOut(duration: 0.1)) {
                onToggleSelection(item)
            }
            return
        }
        #if os(macOS)
        if NSEvent.modifierFlags.contains(.command) {
            onEnterMultiSelect(item)
            return
        }
        #endif
        selectedItem = item
    }

    @ViewBuilder
    private func rowContextMenu(for item: Item) -> some View {
        Button {
            openedItem = item
            selectedItem = item
        } label: {
            Label("Open", systemImage: "doc.text")
        }
        Button {
            NotificationCenter.default.postDiscussItem(DiscussItemPayload(item: item))
        } label: {
            Label("Discuss", systemImage: "bubble.left.and.bubble.right")
        }
        Divider()
        Button("Delete Item", role: .destructive) {
            onDeleteRequest(item)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: searchQuery.isEmpty ? "books.vertical" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.textTertiary)

            if searchQuery.isEmpty {
                Text("Your Library")
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Capture items to start building your knowledge base.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Text("No results for \"\(searchQuery)\"")
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Try different keywords or clear the board filter.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
