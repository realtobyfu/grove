import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var showBoardPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Title field
            TextField("Note title", text: $item.title)
                .textFieldStyle(.plain)
                .font(.groveTitleLarge)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal)

            // Board membership chips
            boardChips
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()
                .padding(.horizontal)

            // Markdown content area with wiki-link support
            RichMarkdownEditor(
                text: Binding(
                    get: { item.content ?? "" },
                    set: { item.content = $0.isEmpty ? nil : $0 }
                ),
                sourceItem: item,
                minHeight: 200
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(item.title)
        .onChange(of: item.title) { _, _ in
            item.updatedAt = .now
        }
        .onChange(of: item.content) { _, _ in
            item.updatedAt = .now
        }
    }

    private var boardChips: some View {
        HStack(spacing: 6) {
            ForEach(item.boards) { board in
                HStack(spacing: 4) {
                    if let hex = board.color {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 6, height: 6)
                    }
                    Text(board.title)
                        .font(.groveBodySmall)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentBadge)
                .clipShape(Capsule())
            }

            Button {
                showBoardPicker = true
            } label: {
                Label("Add to Board", systemImage: "plus")
                    .font(.groveBodySmall)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textSecondary)
            .popover(isPresented: $showBoardPicker) {
                boardPickerPopover
            }

            Spacer()
        }
    }

    private var boardPickerPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add to Board")
                .font(.groveItemTitle)
                .padding(.horizontal)
                .padding(.top, 8)

            if boards.isEmpty {
                Text("No boards yet.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(boards) { board in
                            let isMember = item.boards.contains(where: { $0.id == board.id })
                            Button {
                                toggleBoard(board, isMember: isMember)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isMember ? Color.textPrimary : Color.textSecondary)
                                    if let hex = board.color {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 8, height: 8)
                                    }
                                    Image(systemName: board.icon ?? "folder")
                                        .frame(width: 16)
                                    Text(board.title)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(width: 220)
        .padding(.bottom, 8)
    }

    private func toggleBoard(_ board: Board, isMember: Bool) {
        if isMember {
            item.boards.removeAll { $0.id == board.id }
            item.updatedAt = .now
            try? modelContext.save()
        } else {
            ItemViewModel(modelContext: modelContext).assignToBoard(item, board: board)
        }
    }
}
