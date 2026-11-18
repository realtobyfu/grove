import Foundation
import Observation

/// One reader's find-in-article state: what the bar shows, what the reading
/// surface is asked to search for, and what it reported back.
///
/// The bar writes `query` as the reader types; the surface on screen (Reader
/// mode, the live page, or a PDF) searches for `activeQuery`, steps when a
/// token moves, and answers through `report(_:for:)`. Nothing here knows which
/// surface that is.
@MainActor
@Observable
final class ReaderFindSession {
    /// Whether the find bar is on screen.
    private(set) var isPresented = false
    /// The field's text, exactly as typed.
    var query = ""
    /// What the surface searches for: `query` once typing has paused, or at
    /// once when the reader presses Return. Empty means "no find".
    private(set) var activeQuery = ""
    /// Bumped to step to the next / previous match of `activeQuery`.
    private(set) var forwardToken = 0
    private(set) var backwardToken = 0
    /// Bumped whenever the bar is asked for, so ⌘F with the bar already open
    /// takes the keyboard back to the field.
    private(set) var focusToken = 0
    private(set) var status: ReaderFind.Status = .idle

    /// The query `activeQuery` replaced, and when. See `ownsSelection`.
    private var previousActiveQuery = ""
    private var activeQueryChangedAt = Date.distantPast
    /// How long a match for the previous query may still be reported by the
    /// page after the next query has taken over.
    static let selectionGraceInterval: TimeInterval = 1.0

    /// The bar's count text.
    var statusLabel: String {
        ReaderFind.label(for: status)
    }

    /// Whether Next / Previous have anything to act on.
    var canStep: Bool {
        !query.isEmpty
    }

    // MARK: - Presentation

    /// Show the bar and put the keyboard in its field.
    func present() {
        isPresented = true
        focusToken += 1
    }

    /// Close the bar. Clearing `activeQuery` is what tells the surface to
    /// drop the match it was showing.
    func dismiss() {
        isPresented = false
        query = ""
        setActiveQuery("")
        status = .idle
    }

    // MARK: - Searching

    /// Hand the typed query to the surface. Called once typing pauses.
    func commitQuery() {
        guard isPresented, query != activeQuery else { return }
        setActiveQuery(query)
        // An emptied field has no result to wait for. Otherwise the previous
        // count stays up until the new one lands, so it doesn't flicker.
        if query.isEmpty { status = .idle }
    }

    func findNext() {
        step(forward: true)
    }

    func findPrevious() {
        step(forward: false)
    }

    private func step(forward: Bool) {
        guard isPresented, !query.isEmpty else { return }
        // Return pressed before the typing pause elapsed: this is still the
        // first search for that text, which lands on its first match.
        guard query == activeQuery else {
            setActiveQuery(query)
            return
        }
        if forward {
            forwardToken += 1
        } else {
            backwardToken += 1
        }
    }

    private func setActiveQuery(_ newQuery: String, now: Date = Date()) {
        guard newQuery != activeQuery else { return }
        previousActiveQuery = activeQuery
        activeQueryChangedAt = now
        activeQuery = newQuery
    }

    // MARK: - Selection Ownership

    /// Whether a selection the page reported is one find made, rather than a
    /// passage the reader picked out. WebKit shows a match by selecting it,
    /// and the reader raises its Highlight bar for any selection; the web
    /// panel asks here first so stepping through matches does not summon it.
    ///
    /// The page reports a selection a beat after it changes, so a match for
    /// the previous query can arrive just after the next one took over. For a
    /// short grace interval that one is still find's too.
    func ownsSelection(_ selection: String?, now: Date = Date()) -> Bool {
        guard isPresented else { return false }
        if ReaderFind.isFindSelection(selection, query: activeQuery) { return true }
        guard now.timeIntervalSince(activeQueryChangedAt) < Self.selectionGraceInterval else {
            return false
        }
        return ReaderFind.isFindSelection(selection, query: previousActiveQuery)
    }

    // MARK: - Results

    /// A surface's answer for `query`. Answers for a query that is no longer
    /// the active one — a slow page, a surface that has since left the screen
    /// — are dropped.
    func report(_ status: ReaderFind.Status, for query: String) {
        guard isPresented, !activeQuery.isEmpty, query == activeQuery else { return }
        self.status = status
    }

    /// The reading surface was swapped under an open bar (Reader ↔ Original).
    /// The old surface's count says nothing about the new one, which reports
    /// for itself as soon as it has searched.
    func surfaceDidChange() {
        status = .idle
    }
}
