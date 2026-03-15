# Inbox Triage

## Description
Users can quickly process items in their inbox by swiping on list rows.
Swipe right queues an item for later; swipe left archives it immediately.
The inbox badge count updates in real time as items are triaged.

## Acceptance Criteria
- [ ] Swipe right reveals a "Queue" action (trailing swipe)
- [ ] Swipe left reveals an "Archive" action (leading swipe)
- [ ] Queuing an item moves it to the Queue tab and removes it from Inbox
- [ ] Archiving an item removes it from Inbox with no further destination
- [ ] Badge on the Inbox tab reflects the current unread count
- [ ] Badge updates without requiring a view refresh
- [ ] Actions are accessible via long-press context menu as a fallback

## Edge Cases
- Inbox is empty: show empty state, no swipe targets rendered
- Item is already queued: swipe-right is a no-op (or shows "Already queued" toast)
- Triage during CloudKit sync: optimistic update locally, reconcile on sync completion

## Constraints
- Swipe actions must meet 44pt minimum touch target height
- Archive is non-destructive — items remain in SwiftData, just status changes
- Must work identically on iPhone and iPad (iPad may show inbox in a column)
