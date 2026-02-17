import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query private var allItems: [Item]

    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox }.count
    }
    @Query(sort: \Board.sortOrder) private var boards: [Board]

    var body: some View {
        List(selection: $selection) {
            Section {
                Label {
                    HStack {
                        Text("Inbox")
                        Spacer()
                        if inboxCount > 0 {
                            Text("\(inboxCount)")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.red.opacity(0.8))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: "tray")
                }
                .tag(SidebarItem.inbox)
            }

            Section("Boards") {
                ForEach(boards) { board in
                    Label {
                        HStack(spacing: 6) {
                            if let hex = board.color {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 8, height: 8)
                            }
                            Text(board.title)
                        }
                    } icon: {
                        Image(systemName: board.icon ?? "folder")
                    }
                    .tag(SidebarItem.board(board.id))
                }
            }

            Section {
                Label("Tags", systemImage: "tag")
                    .tag(SidebarItem.tags)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Grove")
    }
}
