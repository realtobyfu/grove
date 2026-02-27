import SwiftUI

/// The main list of items in the library with multi-select support.
struct LibraryListView: View {
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
                LazyVStack(spacing: 0) {
                    ForEach(displayedItems) { item in
                        selectableRow(for: item)
                        Divider()
                            .padding(.leading, isMultiSelectMode ? 68 : 40)
                    }
                }
                .padding(.vertical, Spacing.xs)
                if isMultiSelectMode && !selectedIDs.isEmpty {
                    Spacer().frame(height: 52)
                }
            }
        }
    }

    // MARK: - Selectable Row

    private func selectableRow(for item: Item) -> some View {
        let isItemSelected = selectedIDs.contains(item.id)
        let isHighlighted = isMultiSelectMode ? isItemSelected : selectedItem?.id == item.id

        return HStack(spacing: 0) {
            if isMultiSelectMode {
                Image(systemName: isItemSelected ? "checkmark.circle.fill" : "circle")
                    .font(.groveBody)
                    .foregroundStyle(isItemSelected ? Color.textPrimary : Color.textMuted)
                    .frame(width: 28)
                    .padding(.leading, Spacing.sm)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            LibraryRowView(item: item)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !isMultiSelectMode {
                openedItem = item
                selectedItem = item
            }
        }
        .onTapGesture(count: 1) {
            handleRowTap(item: item)
        }
        .selectedItemStyle(isHighlighted)
        .contextMenu {
            rowContextMenu(for: item)
        }
    }

    private func handleRowTap(item: Item) {
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

// MARK: - Library Row View

struct LibraryRowView: View {
    let item: Item
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.type.iconName)
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

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
                    if !item.tags.isEmpty {
                        Text("\u{00B7}")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                    ForEach(Array(item.tags.prefix(2)), id: \.id) { tag in
                        Text(tag.name)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                    }
                    if item.tags.count > 2 {
                        Text("+\(item.tags.count - 2)")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Spacer()

            // Discuss button — visible on hover
            if isHovered {
                Button {
                    NotificationCenter.default.postDiscussItem(DiscussItemPayload(item: item))
                } label: {
                    Label("Discuss", systemImage: "bubble.left.and.bubble.right")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            Text(item.updatedAt.relativeShort)
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)

            GrowthStageIndicator(stage: item.growthStage)
                .help("\(item.growthStage.displayName) — \(item.depthScore) pts")

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
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Date Extension

extension Date {
    var relativeShort: String {
        let now = Date()
        let diff = now.timeIntervalSince(self)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        if diff < 86400 * 7 { return "\(Int(diff / 86400))d" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}
