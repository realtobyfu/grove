# Testing Conventions

## Test naming

Use the pattern `test_<subject>_<condition>_<expectedResult>`:

```swift
func test_inbox_whenEmpty_showsEmptyState() { ... }
func test_triage_swipeRight_movesItemToQueue() { ... }
func test_sync_onConflict_prefersCloudVersion() { ... }
```

## Doc comments on every test

Every test function must have a doc comment explaining what is being verified and why it matters.
Future loop iterations will not have the context that led to writing this test.

```swift
/// Verifies that archiving an item immediately removes it from the inbox query result.
/// This matters because the @Query filter relies on `status != .inbox`, and a missed
/// status update would leave ghost items in the list.
func test_archive_updatesQueryResult() { ... }
```

## Structure: Arrange / Act / Assert

```swift
func test_queue_updatesItemStatus() async throws {
    // Arrange
    let item = Item(title: "Test", status: .inbox)
    modelContext.insert(item)

    // Act
    try await service.queue(item)

    // Assert
    XCTAssertEqual(item.status, .queued)
}
```

## What to test

- Service layer: use a real in-memory `ModelContainer`, not mocks.
- ViewModel: test state transitions, not UI rendering.
- Do not test private implementation details — test observable behavior.
- Prefer narrow unit tests over broad integration tests for fast feedback.

## XCTest async

```swift
func test_async_operation() async throws {
    // Use async/throws — no XCTestExpectation needed for async code
    let result = try await sut.perform()
    XCTAssertEqual(result, expected)
}
```
