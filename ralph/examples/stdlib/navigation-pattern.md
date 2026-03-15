# Navigation Pattern

## Layout selection

- **iPhone (regular/compact width)**: `TabView` with five tabs.
- **iPad (regular width)**: `NavigationSplitView` with three columns (sidebar / content / detail).
- Detect with `@Environment(\.horizontalSizeClass)`, not `UIDevice` or `#if os(iOS)`.

```swift
if horizontalSizeClass == .compact {
    TabView { ... }
} else {
    NavigationSplitView { ... } content: { ... } detail: { ... }
}
```

## Deep links

- Scheme: `grove://item/{uuid}`, `grove://board/{uuid}`, `grove://chat/{uuid}`
- Handle in `.onOpenURL` at the root scene level.
- Route to a `NavigationPath` or selection binding — never push imperatively.

## Sheets vs popovers

| Context | Use |
|---------|-----|
| iPhone, any picker/inspector | Sheet with `.presentationDetents` |
| iPad, any picker/inspector | Popover anchored to the triggering control |
| Destructive confirmation | `.confirmationDialog` |
| Inline quick-action | Context menu (`.contextMenu`) |

```swift
// Platform-adaptive picker
.ifLet(presentedItem) { view, item in
    if horizontalSizeClass == .compact {
        view.sheet(item: ...) { ItemPicker(...) }
    } else {
        view.popover(item: ...) { ItemPicker(...) }
    }
}
```

## NavigationStack

- Use `NavigationStack(path:)` with typed `NavigationPath` for programmatic navigation.
- Define a `AppRoute` enum conforming to `Hashable` for all destinations.
- Keep navigation state in the root ViewModel or scene-level `@State`, not inside child views.
