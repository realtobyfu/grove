import SwiftUI
import SwiftData

/// iPad 3-column NavigationSplitView layout.
/// Sidebar routes selection to the content column. The detail column
/// will show item reader / inspector once P5 is implemented.
struct iPadRootView: View {
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Course.createdAt) private var courses: [Course]

    @State private var selection: SidebarItem? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    /// Persists sidebar selection per scene for iPad multi-window support.
    @SceneStorage("iPadSidebarSelection") private var storedSelection: String = "home"

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            iPadSidebarView(selection: $selection)
        } content: {
            contentForSelection
        } detail: {
            detailPlaceholder
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            // Restore sidebar selection from scene storage on launch
            if let restored = SidebarItem(sceneStorageValue: storedSelection) {
                selection = restored
            }
        }
        .onChange(of: selection) { _, newSelection in
            // Persist sidebar selection changes to scene storage
            if let newSelection {
                storedSelection = newSelection.sceneStorageValue
            }
        }
        .onChange(of: deepLinkRouter.selectedSidebarItem) { _, newItem in
            if let newItem {
                selection = newItem
            }
        }
    }

    // MARK: - Content routing

    @ViewBuilder
    private var contentForSelection: some View {
        switch selection {
        case .home:
            Text("Home")
                .font(.groveTitle)
                .foregroundStyle(Color.textSecondary)
                .navigationTitle("Home")
        case .inbox:
            Text("Inbox")
                .font(.groveTitle)
                .foregroundStyle(Color.textSecondary)
                .navigationTitle("Inbox")
        case .library:
            Text("Library")
                .font(.groveTitle)
                .foregroundStyle(Color.textSecondary)
                .navigationTitle("Library")
        case .board(let boardID):
            if let board = boards.first(where: { $0.id == boardID }) {
                Text(board.title)
                    .font(.groveTitle)
                    .foregroundStyle(Color.textSecondary)
                    .navigationTitle(board.title)
            } else {
                ContentUnavailableView("Board Not Found",
                                       systemImage: "folder",
                                       description: Text("This board may have been deleted."))
            }
        case .course(let courseID):
            if let course = courses.first(where: { $0.id == courseID }) {
                Text(course.title)
                    .font(.groveTitle)
                    .foregroundStyle(Color.textSecondary)
                    .navigationTitle(course.title)
            } else {
                ContentUnavailableView("Course Not Found",
                                       systemImage: "graduationcap",
                                       description: Text("This course may have been deleted."))
            }
        case .graph:
            Text("Knowledge Graph")
                .font(.groveTitle)
                .foregroundStyle(Color.textSecondary)
                .navigationTitle("Graph")
        case .settings:
            Text("Settings")
                .font(.groveTitle)
                .foregroundStyle(Color.textSecondary)
                .navigationTitle("Settings")
        case nil:
            ContentUnavailableView("Grove",
                                   systemImage: "leaf",
                                   description: Text("Select an item from the sidebar."))
        }
    }

    @ViewBuilder
    private var detailPlaceholder: some View {
        ContentUnavailableView("No Selection",
                               systemImage: "doc.text",
                               description: Text("Select an item to read."))
    }
}
