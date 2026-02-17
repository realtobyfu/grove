import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case inbox
    case board(UUID)
    case tags
}

struct ContentView: View {
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @State private var selection: SidebarItem? = .inbox
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            HStack(spacing: 0) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector {
                    Divider()
                    InspectorPanelView()
                        .frame(width: 280)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation {
                            showInspector.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help(showInspector ? "Hide Inspector" : "Show Inspector")
                    .keyboardShortcut("]", modifiers: .command)
                }
            }
        }
        .frame(minWidth: 1200, minHeight: 800)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .inbox:
            PlaceholderView(
                icon: "tray",
                title: "Inbox",
                message: "Captured items will appear here for triage."
            )
        case .board(let boardID):
            if let board = boards.first(where: { $0.id == boardID }) {
                PlaceholderView(
                    icon: board.icon ?? "square.grid.2x2",
                    title: board.title,
                    message: "Items in this board will appear here."
                )
            } else {
                PlaceholderView(
                    icon: "square.grid.2x2",
                    title: "Board",
                    message: "Board not found."
                )
            }
        case .tags:
            PlaceholderView(
                icon: "tag",
                title: "Tags",
                message: "Browse and manage your tags here."
            )
        case nil:
            PlaceholderView(
                icon: "leaf",
                title: "Grove",
                message: "Select an item from the sidebar to get started."
            )
        }
    }
}

struct PlaceholderView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InspectorPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inspector")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            Text("Select an item to see details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()
        }
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
