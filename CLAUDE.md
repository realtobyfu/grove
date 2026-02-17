# Project: Grove

## AUTONOMOUS MODE — NO HUMAN IN THE LOOP

You are running inside an autonomous Ralph loop. There is NO human operator. Do NOT ask questions, present choices, or wait for input. You must act independently on every iteration.

### YOUR EXACT WORKFLOW EVERY TIME:

1. Read `prd.json` in the project root
2. Find the FIRST user story where `"passes": false` (sorted by `"storyId"`)
3. Read its `"acceptanceCriteria"` carefully
4. Read `progress.txt` (if it exists) for learnings from previous iterations
5. Read `spec.md` for any relevant design/architecture details
6. IMPLEMENT the story completely — write all code, create all files
7. Run quality checks: `xcodebuild -scheme Grove -destination 'platform=macOS' build`
8. If build fails, fix the errors and retry (up to 3 attempts)
9. `git add -A && git commit -m "S[X]: [story title]"`
10. Update `prd.json`: set the story's `"passes"` to `true`
11. Append what you learned to `progress.txt`
12. Output `<promise>COMPLETE</promise>`

### CRITICAL RULES:
- **START IMMEDIATELY.** Do not summarize the project state. Do not list what needs to be done. Just do it.
- **ONE STORY PER ITERATION.** Implement exactly one story, then stop.
- **NEVER ASK QUESTIONS.** If something is ambiguous, make the best choice and document it in progress.txt.
- **If the build fails after 3 attempts**, document the blocker in progress.txt, skip this story, and output `<promise>COMPLETE</promise>` so the next iteration can try a different approach.
- **If Tuist is needed**, run `tuist generate` before building. If tuist is not available, use xcodebuild directly with the existing .xcodeproj.

---

## Overview
A Mac-native knowledge companion that captures articles, videos, and ideas into boards with auto-tagging, then actively nudges users to engage with their saved knowledge.

## Tech Stack
- **Platform**: macOS 15+ (Sequoia)
- **Language**: Swift 6
- **UI**: SwiftUI
- **Persistence**: SwiftData
- **Architecture**: MVVM with @Observable
- **Markdown**: apple/swift-markdown + TextKit 2
- **Testing**: Swift Testing

## Build & Run
```bash
tuist generate      # Generate .xcodeproj (run after changing Project.swift)
tuist edit          # Edit manifest with autocomplete
tuist clean         # Clear generated files

# Build from command line
xcodebuild -scheme Grove -destination 'platform=macOS' build

# Run tests
xcodebuild -scheme Grove -destination 'platform=macOS' test
```

**Rule**: Never edit .xcodeproj directly — `Project.swift` is the source of truth.

## Project Structure
```
Grove/
├── Grove/
│   ├── GroveApp.swift              # @main, WindowGroup + MenuBarExtra
│   ├── Models/
│   │   ├── Item.swift              # @Model — core entity (article, video, note, lecture)
│   │   ├── Board.swift             # @Model — domain container
│   │   ├── Tag.swift               # @Model — connective tissue
│   │   ├── Connection.swift        # @Model — item-to-item knowledge graph edges
│   │   ├── Annotation.swift        # @Model — notes on items
│   │   └── Nudge.swift             # @Model — proactive resurfacing
│   ├── Views/
│   │   ├── Sidebar/
│   │   ├── Inbox/
│   │   ├── Board/
│   │   ├── Item/
│   │   ├── Inspector/
│   │   ├── Capture/
│   │   ├── Search/
│   │   ├── Nudge/
│   │   └── Settings/
│   ├── ViewModels/
│   ├── Services/
│   │   ├── CaptureService.swift    # URL metadata fetching, OpenGraph extraction
│   │   ├── AutoTagService.swift    # AI tagging pipeline
│   │   ├── NudgeEngine.swift       # Nudge generation and scheduling
│   │   └── URLMetadataFetcher.swift
│   ├── Markdown/
│   │   ├── GroveMarkdownParser.swift   # swift-markdown with [[wiki-link]] support
│   │   ├── GroveTextView.swift         # TextKit 2 markdown rendering
│   │   └── WikiLinkResolver.swift
│   ├── Extensions/
│   └── Resources/
│       └── Assets.xcassets
└── GroveTests/
```

## Architecture Rules

### Layout
Three-column `NavigationSplitView`:
- **Sidebar**: Inbox (with badge), Boards list, Tags browser
- **Content**: Adapts per context — board grid, inbox triage, item reader
- **Inspector**: Collapsible detail panel for selected item

### MVVM with SwiftData
ViewModels own queries and mutations. Views are thin display layers. SwiftData `@Model` classes are the single source of truth — no DTOs, no mapping layers.

```swift
@Observable
@MainActor
final class BoardViewModel {
    private let modelContext: ModelContext

    var boards: [Board] = []
    var selectedBoard: Board?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchBoards() {
        let descriptor = FetchDescriptor<Board>(sortBy: [SortDescriptor(\.sortOrder)])
        boards = (try? modelContext.fetch(descriptor)) ?? []
    }

    func createBoard(title: String, icon: String?, color: String?) {
        let board = Board(title: title, icon: icon, color: color)
        modelContext.insert(board)
        fetchBoards()
    }
}
```

### SwiftData Model Pattern
```swift
@Model
final class Item {
    var id: UUID
    var title: String
    var type: ItemType
    var status: ItemStatus
    var createdAt: Date
    var updatedAt: Date

    @Relationship(inverse: \Board.items) var boards: [Board]
    @Relationship var tags: [Tag]
    @Relationship(deleteRule: .cascade) var annotations: [Annotation]

    init(title: String, type: ItemType) {
        self.id = UUID()
        self.title = title
        self.type = type
        self.status = .inbox
        self.createdAt = .now
        self.updatedAt = .now
        self.boards = []
        self.tags = []
        self.annotations = []
    }
}
```

Enums used in models must conform to `String, Codable`. Use `@Relationship` with explicit inverse and delete rules.

### Dependency Injection
Pass `ModelContext` through environment or init injection. No singletons. Services take `ModelContext` in their initializer.

```swift
// In GroveApp.swift
@main
struct GroveApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Item.self, Board.self, Tag.self, Connection.self, Annotation.self, Nudge.self])
    }
}

// In views, access via environment
@Environment(\.modelContext) private var modelContext
```

## Coding Standards

### Do
- Use `async/await` for all async work
- Use `@Observable` (not ObservableObject)
- Use `NavigationSplitView` for the three-column layout
- Use `@Query` in views for simple read-only lists, ViewModels for complex logic
- Use `guard` for early exits
- Use SF Symbols for all icons
- Use system font (no custom fonts)
- Support dark mode as the primary design target
- Extract views > 50 lines into subviews
- Use `.sidebar` material and native macOS styling
- Commit after each working milestone

### Don't
- Force unwrap (`!`) without justification
- Put business logic in Views
- Use singletons — inject dependencies
- Use deprecated APIs (`NavigationView`, `List` selection patterns, etc.)
- Use `ObservableObject` / `@Published` / `@StateObject` — use `@Observable` instead
- Create DTOs or mapping layers over SwiftData models
- Use UIKit — this is a macOS app, use AppKit interop only when SwiftUI has no equivalent
- Add third-party dependencies without justification — prefer Apple frameworks

## Key Interactions

### Quick Capture
`MenuBarExtra` with global keyboard shortcut (`⌘+Shift+K`). Floating panel: paste URL → auto-fetch metadata → save to Inbox. Must feel instant.

### Inbox Triage
Card stack with three actions: Keep (→ active, assign board), Later (stays in inbox), Drop (→ dismissed). Keyboard driven: `J/K` navigate, `1/2/3` for actions.

### `[[` Wiki-Links
In any markdown text field, typing `[[` opens a fuzzy-search popover of all Items. Selecting one creates a `Connection` between the current item and the linked item.

### Nudge Bar
Non-blocking banner at top of content area. One nudge at a time. Dismissable. Never modal.

## Testing Approach
```swift
import Testing
import SwiftData

@Test func boardViewModel_createsBoard() async {
    // Arrange
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Board.self, Item.self, Tag.self,
        configurations: config
    )
    let context = ModelContext(container)
    let vm = BoardViewModel(modelContext: context)

    // Act
    vm.createBoard(title: "Swift & iOS", icon: "swift", color: "#F05138")

    // Assert
    #expect(vm.boards.count == 1)
    #expect(vm.boards.first?.title == "Swift & iOS")
}
```

Use in-memory `ModelContainer` for all tests. Focus on: ViewModel logic, SwiftData queries, service logic. Skip for now: UI tests, snapshot tests.

## Design Principles
- **Mac-native**: Should look like Apple made it. Use system components, vibrancy, `.sidebar` material.
- **Dark mode first**: Engineers live in dark mode.
- **Keyboard-first**: Every action reachable via keyboard shortcut.
- **Zero-friction capture**: If saving takes > 3 seconds, the system failed.
- **Progressive engagement**: A bare item is a bookmark. One with connections and annotations is knowledge. Make this progression visible.

## Reference
Full product spec: see `spec.md` in the repo root.