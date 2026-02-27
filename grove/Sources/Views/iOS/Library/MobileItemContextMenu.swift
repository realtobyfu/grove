import SwiftUI
import SwiftData

/// Context menu for item cards on iOS — provides Open, Add to Board,
/// Archive, Discuss, Share, and Delete actions with confirmation.
struct MobileItemContextMenu: ViewModifier {
    let item: Item
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    @State private var showDeleteConfirmation = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                // Add to Board sub-menu
                Menu {
                    ForEach(boards) { board in
                        Button {
                            let viewModel = ItemViewModel(modelContext: modelContext)
                            viewModel.assignToBoard(item, board: board)
                        } label: {
                            Label(board.title, systemImage: board.icon ?? "folder")
                        }
                    }
                } label: {
                    Label("Add to Board", systemImage: "folder.badge.plus")
                }

                Divider()

                // Archive
                Button {
                    item.status = .archived
                    item.updatedAt = .now
                    try? modelContext.save()
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }

                Divider()

                // Delete
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } preview: {
                // Preview: title + source + first 3 lines of content
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(item.title)
                        .font(.groveBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textPrimary)

                    if let sourceURL = item.sourceURL,
                       let host = URL(string: sourceURL)?.host(percentEncoded: false) {
                        Text(host)
                            .font(.groveMeta)
                            .foregroundStyle(Color.textMuted)
                    }

                    if let content = item.content, !content.isEmpty {
                        Text(content)
                            .font(.groveBodySecondary)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(3)
                    }
                }
                .padding(Spacing.md)
                .frame(width: 280)
            }
            .alert("Delete Item?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    let viewModel = ItemViewModel(modelContext: modelContext)
                    viewModel.deleteItem(item)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \"\(item.title)\".")
            }
    }
}

extension View {
    func mobileItemContextMenu(item: Item) -> some View {
        modifier(MobileItemContextMenu(item: item))
    }
}
