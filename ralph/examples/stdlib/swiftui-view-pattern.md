# SwiftUI View Pattern

## ViewModel ownership

- Use `@Observable` (Swift 5.9 Observation framework), never `ObservableObject`.
- Views receive ViewModels via `@State` when the view owns its lifecycle, or via the environment when sharing across siblings.
- Pass ViewModels down as plain values — do not use `@EnvironmentObject` for new code.

```swift
// Correct
@State private var viewModel = InboxViewModel()

// Wrong
@ObservedObject var viewModel: InboxViewModel
```

## State separation

- `@State` — UI-only ephemeral state (is a sheet showing, what's the current text field value).
- ViewModel properties — business state that survives navigation or needs persistence.
- Never put SwiftData `@Query` results in a ViewModel; query directly in the view.

## View composition

- Extract subviews when a body exceeds ~40 lines or when a subview has independent state.
- Prefer computed `var` properties on the view struct over inline conditional blocks for named sub-components.
- Do not pass `Binding` into sub-views unless the child needs to mutate the value directly.

## Layout conventions

- Use `ViewThatFits` for adaptive layouts before reaching for `GeometryReader`.
- `@ScaledMetric` for all non-font CGFloat constants (spacing, icon sizes, corner radii).
- `Font.custom(_:size:relativeTo:)` for all custom fonts — never hardcode a size without a `TextStyle`.

## Modifiers

- Apply `.contentShape(Rectangle())` to any tappable area smaller than 44×44pt.
- Use `.sensoryFeedback` (iOS 17+) for haptics instead of `UIImpactFeedbackGenerator`.
- Prefer `.overlay` and `.background` over `ZStack` for decorative layers.
