# CLAUDE.md — Grove iOS/iPad

## Build & Test (use xclaude MCP tools, NOT raw commands)
- Build: use `xcode_build` tool (scheme: "grove-ios", destination: iPhone 16 simulator)
- Test: use `xcode_test` tool (scheme: "groveTests")
- Screenshot: use `simulator_screenshot` after UI changes
- UI verify: use `idb_describe` to check accessibility tree
- If xclaude tools unavailable, fallback: `tuist generate && xcodebuild -scheme grove-ios -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|warning:" | head -20`

## Project Structure
- Tuist-managed project. Run `tuist generate` after changing Project.swift
- Shared code: grove/Sources/{Models,Services,ViewModels,Utilities,Extensions}/
- iOS views: grove/Sources/Views/iOS/
- Shared views: grove/Sources/Views/Shared/
- macOS views: grove/Sources/Views/macOS/
- Share Extension: grove/ShareExtension/
- Specs: specs/grove-mobile-spec.md

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
- All text: use @ScaledMetric for Dynamic Type
- SF Symbols: .medium weight on mobile

## SwiftData
- Shared ModelContainer via App Group: group.dev.tuist.grove
- Same iCloud container: iCloud.dev.tuist.grove
- Models are 100% shared with macOS. No schema changes for iOS.
- Share Extension writes to shared store, main app does CloudKit sync.

## Key Conventions
- Prefer ViewThatFits or GeometryReader breakpoints over #if os() for responsive layout
- iPad popovers for pickers/inspectors, iPhone uses sheets with detents
- Swipe actions on List rows for inbox triage (right=queue, left=archive)
- Deep links: grove://item/{uuid}, grove://board/{uuid}, grove://chat/{uuid}

## Gotchas Discovered
<!-- Ralph updates this section as it learns -->
- UIDevice.current is @MainActor in Swift 6. Font statics on iOS use @MainActor + Platform.isIPad helper. Safe because fonts are only read from SwiftUI view bodies.
- Font.custom(_:size:relativeTo:) is the correct way to enable Dynamic Type for custom fonts on iOS. No @ScaledMetric needed for Font tokens (use @ScaledMetric for non-font CGFloat values like spacing).
- Both targets (grove + grove-ios) compile ALL files in grove/Sources/. iOS-only modifiers (.keyboardType, .textInputAutocapitalization, .navigationBarTitleDisplayMode) need `#if os(iOS)` guards even in Views/iOS/ files.
- SwiftData `#Predicate` does not support enum member access (`.inbox`). Use `@Query` without filter + computed property instead.
