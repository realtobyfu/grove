# CLAUDE.md — Grove iOS/iPad

## Build & Test (use xclaude MCP tools)
- Build: `xcode_build` (scheme: "grove-ios", destination: iPhone 16 simulator)
- Test: `xcode_test` (scheme: "groveTests")
- Screenshot: `simulator_screenshot` after UI changes
- UI verify: `idb_describe` to check accessibility tree

## Project Structure
- Tuist-managed. Run `tuist generate` after changing Project.swift.
- Shared code: grove/Sources/{Models,Services,ViewModels,Utilities,Extensions}/
- Views: grove/Sources/Views/{iOS,Board,Chat,Home,Inbox,Library,...} (feature-grouped; iOS-specific in iOS/)
- Share Extension: grove/ShareExtension/
- UX spec: /DESIGN.md

## Architecture
- SwiftUI + MVVM. @Observable ViewModels (NOT ObservableObject)
- Views own UI state (@State). ViewModels own business state.
- Services behind protocol interfaces
- iPhone: TabView (Home/Inbox/Library/Chat/More)
- iPad: NavigationSplitView (3-column). Falls back to TabView in compact width.
- Use `@Environment(\.horizontalSizeClass)` over `#if os(iOS)` for layout
- Use `#if os()` only for: scene types, platform APIs (NS* vs UI*), notification APIs

## Design System
- Monochromatic. No accent colors. Hierarchy through typography weight/size/contrast.
- Min touch target: 44x44pt on iOS
- Fonts: Newsreader (titles), IBM Plex Sans (body), IBM Plex Mono (meta)
- Font tokens: `Font.custom(_:size:relativeTo:)` for Dynamic Type. `@ScaledMetric` for non-font CGFloat values (spacing, sizes).
- SF Symbols: .medium weight on mobile

## SwiftData
- Shared ModelContainer via App Group: group.dev.tuist.grove
- iCloud container: iCloud.dev.tuist.grove
- Models are 100% shared with macOS. No schema changes for iOS.
- Share Extension writes to shared store, main app does CloudKit sync.

## Key Conventions
- iPad popovers for pickers/inspectors, iPhone uses sheets with detents
- Swipe actions on List rows for inbox triage (right=queue, left=archive)
- Deep links: grove://item/{uuid}, grove://board/{uuid}, grove://chat/{uuid}

## Gotchas
<!-- Ralph updates this section as it learns -->
- `UIDevice.current` is @MainActor in Swift 6. Use @MainActor + Platform.isIPad helper.
- Both targets (grove + grove-ios) compile ALL files in grove/Sources/. iOS-only modifiers (.keyboardType, .textInputAutocapitalization, .navigationBarTitleDisplayMode) need `#if os(iOS)` guards even in Views/iOS/ files.
- SwiftData `#Predicate` does not support enum member access (`.inbox`). Use `@Query` without filter + computed property instead.
- GroveShareExtension compiles all of grove/Sources/. `@main` guarded with `#if !SHARE_EXTENSION`. `UIApplication.shared` unavailable — use `@Environment(\.openURL)`.
- Tuist does not support mixing `sources` (glob) and `buildableFolders` for overlapping paths. Use `buildableFolders` consistently + compilation conditions for exclusions.
