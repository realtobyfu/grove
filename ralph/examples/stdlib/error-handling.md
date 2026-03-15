# Error Handling

## General rules

- Propagate errors via `throws` / `async throws`. Never swallow errors silently.
- Use typed errors (enums conforming to `Error`) at service boundaries.
- At the UI boundary, convert errors to user-facing messages in the ViewModel, not in the view.

## Error type conventions

```swift
enum ItemServiceError: LocalizedError {
    case notFound(UUID)
    case syncConflict(Item, Item)
    case storageFailure(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Item could not be found."
        case .syncConflict: return "A sync conflict was detected."
        case .storageFailure: return "Could not save changes."
        }
    }
}
```

## ViewModel pattern

```swift
@Observable final class ItemViewModel {
    var errorMessage: String?

    func load() async {
        do {
            items = try await service.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

## User-facing display

- Use `.alert(isPresented:)` bound to a `Bool` derived from `errorMessage != nil`.
- Never show raw error types or stack traces to users.
- For recoverable errors, offer a retry action in the alert.

## Logging

- `Logger` (os.log) for all errors at service layer: `logger.error("fetch failed: \(error)")`
- Include context: which item, which operation, relevant IDs.
- Do not log PII (user content, email addresses).
