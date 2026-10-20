# Learning in Grove

Save a question from a passage, reflection, or note, then return for a short review. Today and board pages show a compact **Flashcards** row with a ready count, **Review** action, and options menu for flashcards and **Focus & session length**. With nothing due, **Open** leads to the library. Board reviews scope to that board; general reviews use the saved focus boards. Empty focus includes the whole library.

## Workflow

- Create from a reader selection, reflection, note, or the library. Cards snapshot source title, passage, URL, identifiers, available locator, and board IDs.
- Author the question, answer, and optional hints, one cue per line. **Suggest a question** uses the existing LLM provider and passage, requires an exact supporting quote, and waits for manual review/save. Creation and review work offline without AI.
- Review shows the question first. **Hint**, **Read**, and **Show answer** provide immediate help. The passage view opens the full resource and returns to the question.
- Desktop creation uses the reader's contextual rail. Desktop review sheets are fixed at 680 × 500 points, so **Read** normally opens a passage sheet. Inline passages require a review width of at least 760 points. Shortcuts: Space (answer), H (hint), R (passage), 1–4 (ratings), disabled while a passage or editor is open.
- **Try recalling again** hides the answer and cues but retains support flags. Skipping records no review. **Finish** closes immediately; completion appears only when the session is exhausted, with a short summary and one **Done** action. The 1-, 3-, and 5-minute preferences target 2, 5, and 8 cards, respectively; users can stop anytime.

## Scheduling and persistence

`LearningService` owns main-actor persistence. `FlashcardReview` stores append-only rating events separately from reading engagement. Stable event UUIDs make retries idempotent, preserving timestamps and rejecting conflicting reuse. Imported duplicates reconcile deterministically and conservatively.

The scheduler is a conservative initial policy, not FSRS:

| Rating | Next review without support |
| --- | --- |
| Forgot | 10 minutes; reset the independent interval |
| With effort | Half the previous interval, with a 1-day minimum |
| Recalled | Initially 1 day; eligible later successes double the interval |
| Easily | Initially 3 days; eligible later successes triple the interval |

Growth requires independent successes at least 24 hours apart and caps at 120 days. Rapid repeats do not compound intervals. Hints and reading count as support, including reading after revealing the answer. Supported non-**Forgot** results return in 1 day without establishing independent recall; **Forgot** still returns in 10 minutes.

Question, answer, or hint edits start a new revision and scheduling baseline. Prior events remain history. Fingerprints distinguish concurrent edits sharing a numeric revision; only matching evidence schedules the current content. Unchanged saves and pause/resume preserve the baseline. Card deletion tombstones the card and retains events; source deletion preserves its captured passage and provenance.

Retain **SwiftData + CloudKit**: cards, reviews, and focus preferences use the shared schema. No SQLiteData/SQLite migration is included. Presentation state stays local; imported review evidence rebuilds due dates.

The small/medium iOS widget reads an App Group snapshot of card presence, session length, optional board ID, and update time. It exposes no question text or live due count. Its URL (`grove://review`, optionally `?board=<UUID>`) and **Review in Grove** App Intent open the app, which computes the current queue.

## Preview

Use a Debug build with these launch arguments in either app scheme:

```text
--learning-demo -grove.onboarding.completedVersion 1
```

For an installed Debug app on the booted iOS simulator:

```sh
xcrun simctl launch booted dev.tuist.grove --learning-demo -grove.onboarding.completedVersion 1
```

`LearningDemo` supplies an in-memory board, note, and two due cards, without opening the persistent library or enabling its CloudKit sync. Relaunch resets the fixture; Release builds ignore the flag. Use it for UI inspection; validate sync with the normal launch path.

## Verification

`LearningTests.swift` has 16 automated cases covering scheduling, support, deduplication/retries, revisions/forks, focus/budgets, deletion/provenance, context safety, and draft quotes. `SyncServiceTests.swift` covers status transitions. Record actual build/test results separately; this coverage does not establish CloudKit delivery or native UI behavior.

Before release, check the following on the native app:

- **Phone navigation:** verify four native tabs: **Today**, **Library**, **Following**, and **Chat**. Open Settings from the toolbar gear and boards from Library. Check that Following and learning screens keep concise copy without the removed helper/coaching text.
- **Phone learning:** create from a selected passage and reflection; edit optional hints; follow Hint → Read → retry → Show answer → rating. Check Dynamic Type, VoiceOver, long text, keyboard dismissal, empty queues, AI failure, immediate Finish dismissal, and a single Done action after exhausting the session.
- **Desktop/iPad:** create beside the reader without losing the selection; check the default 680 × 500 desktop review and passage sheet, plus inline reading when hosted at least 760 points wide; read the full resource and return; verify keyboard shortcuts do not fire in text fields or source presentations.
- **Widget/system entry:** install both widget sizes; change focus and session length; test warm and cold launches, a board link, the App Intent, and a stale snapshot with no currently due cards. Check extension signing and App Group access on a physical phone.
- **Two physical devices, same iCloud account:** create on one and review on the other; go offline on both, review the same card, reconnect in either order, and verify convergence without duplicated interval growth. Check unavailable-account and sync-error UI rather than assuming enabled sync means completed transfer.
- **Deletion and edits across devices:** delete a source and retain its saved passage; pause/resume and delete a card; rewrite a reviewed card while the other device is offline. After delivery, verify tombstones exclude deleted cards, history remains, only the winning content's evidence schedules it, and unchanged saves do not postpone the new revision.

Physical-device CloudKit conflict/offline delivery and WidgetKit refresh behavior remain required validation. An in-memory test or simulator preview cannot establish those results.
