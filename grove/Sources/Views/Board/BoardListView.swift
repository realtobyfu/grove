import SwiftUI
import SwiftData

struct BoardListView: View {
    let items: [Item]
    let canReorder: Bool
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    var itemContextMenu: (Item) -> AnyView
    var onMove: (IndexSet, Int) -> Void

    var body: some View {
        if canReorder {
            reorderableList
        } else {
            staticList
        }
    }

    private var reorderableList: some View {
        List {
            ForEach(items) { item in
                listRow(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        openedItem = item
                        selectedItem = item
                    }
                    .onTapGesture(count: 1) {
                        selectedItem = item
                    }
                    .selectedItemStyle(selectedItem?.id == item.id)
                    .contextMenu { itemContextMenu(item) }
            }
            .onMove(perform: onMove)
        }
        .listStyle(.plain)
    }

    private var staticList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    listRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            openedItem = item
                            selectedItem = item
                        }
                        .onTapGesture(count: 1) {
                            selectedItem = item
                        }
                        .selectedItemStyle(selectedItem?.id == item.id)
                        .transition(.opacity.combined(with: .slide))
                        .contextMenu { itemContextMenu(item) }
                }
            }
            .cardStyle(cornerRadius: 6)
            .animation(.easeInOut(duration: 0.2), value: items.map(\.id))
            .padding()
        }
    }

    private func listRow(item: Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.type.iconName)
                .font(.groveMeta)
                .foregroundStyle(Color.textMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                if let url = item.sourceURL {
                    Text(url)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                if !item.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.tags.prefix(2)) { tag in
                            TagChip(tag: tag, mode: .capsule)
                        }
                        if item.tags.count > 2 {
                            Text("+\(item.tags.count - 2)")
                                .font(.groveBadge)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }

            Spacer()

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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
