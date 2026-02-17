import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Bindable var item: Item
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var showBoardPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Title field
            TextField("Note title", text: $item.title)
                .textFieldStyle(.plain)
                .font(.title2)
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
            WikiLinkTextEditor(
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
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary)
                .clipShape(Capsule())
            }

            Button {
                showBoardPicker = true
            } label: {
                Label("Add to Board", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .popover(isPresented: $showBoardPicker) {
                boardPickerPopover
            }

            Spacer()
        }
    }

    private var boardPickerPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add to Board")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            if boards.isEmpty {
                Text("No boards yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(boards) { board in
                            let isMember = item.boards.contains(where: { $0.id == board.id })
                            Button {
                                if isMember {
                                    item.boards.removeAll { $0.id == board.id }
                                } else {
                                    item.boards.append(board)
                                }
                                item.updatedAt = .now
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isMember ? .blue : .secondary)
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
}
