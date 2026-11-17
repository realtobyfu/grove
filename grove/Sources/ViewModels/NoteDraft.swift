import Foundation
import SwiftData

/// The text of a note being written, and its way into the store.
///
/// Both note surfaces — the page in the detail column and the quick writer in
/// the rail — hold one of these. It saves a moment after the last keystroke
/// rather than only when the surface closes, so quitting, a crash, or the rail
/// being taken over mid-sentence loses at most the last second of typing.
@MainActor
@Observable
final class NoteDraft {
    enum SaveState: Equatable {
        /// Nothing written and nothing stored.
        case empty
        /// There is text the store does not have yet.
        case edited
        case saved
        case failed

        /// The word shown in the folio line. Nil for an untouched draft.
        var label: String? {
            switch self {
            case .empty: nil
            case .edited: "Edited"
            case .saved: "Saved"
            case .failed: "Not saved"
            }
        }
    }

    /// What a note is called until it is given a title. Stored as the item's
    /// title; shown as an empty title field with a placeholder.
    static let untitledTitle = "Untitled Note"

    /// How long typing has to pause before the draft is written.
    static let saveDelay: Duration = .milliseconds(800)

    var title = ""
    var content = ""
    private(set) var state: SaveState = .empty
    /// The stored note: the one opened for editing, or the one this draft
    /// created on its first save.
    private(set) var item: Item?

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var boardID: UUID?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isConfigured = false
    /// True when `item` was created by this draft rather than opened.
    @ObservationIgnored private var createdItem = false
    /// The title and content as last read from or written to the store. The
    /// draft only writes a field it changed relative to these, so a rename in
    /// the inspector or a sync arriving mid-session is taken in, not undone.
    @ObservationIgnored private var baselineTitle = NoteDraft.untitledTitle
    @ObservationIgnored private var baselineContent: String?
    /// The last save threw; the next one must reach the store even if the
    /// model already holds the draft's text.
    @ObservationIgnored private var needsStoreSave = false

    var hasText: Bool {
        !trimmedTitle.isEmpty || !trimmedContent.isEmpty
    }

    /// True once the note has been deleted out from under the surface.
    /// Writing to a deleted model resurrects garbage in the store, so every
    /// save path bails on this.
    var isItemDeleted: Bool {
        guard let item else { return false }
        return item.isDeleted || item.modelContext == nil
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Points the draft at an existing note, or at nothing for a new one.
    /// Safe to call from `onAppear`: only the first call takes effect.
    ///
    /// - Parameter isFresh: the note was created empty moments ago for this
    ///   surface, so leaving it empty should remove it again.
    func configure(item: Item?, boardID: UUID?, modelContext: ModelContext, isFresh: Bool = false) {
        guard !isConfigured else { return }
        isConfigured = true
        self.modelContext = modelContext
        self.boardID = boardID
        self.item = item
        createdItem = isFresh
        if let item {
            title = item.title == Self.untitledTitle ? "" : item.title
            content = item.content ?? ""
            baselineTitle = Self.normalizedTitle(item.title)
            baselineContent = Self.normalizedContent(item.content)
            state = .saved
        }
    }

    private static func normalizedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? untitledTitle : trimmed
    }

    private static func normalizedContent(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Takes in a title or body that changed in the store (inspector, sync)
    /// while the draft's own copy of that field was untouched.
    private func pullExternalChanges() {
        guard let item, !isItemDeleted else { return }
        let itemTitle = Self.normalizedTitle(item.title)
        if itemTitle != baselineTitle, storedTitle == baselineTitle {
            baselineTitle = itemTitle
            title = itemTitle == Self.untitledTitle ? "" : itemTitle
        }
        let itemContent = Self.normalizedContent(item.content)
        if itemContent != baselineContent, storedContent == baselineContent {
            baselineContent = itemContent
            content = item.content ?? ""
        }
    }

    /// Call when the title or the body changes.
    func textDidChange() {
        guard isConfigured, !isItemDeleted else { return }
        pullExternalChanges()
        guard hasUnsavedChanges else {
            saveTask?.cancel()
            saveTask = nil
            state = item == nil ? .empty : .saved
            return
        }

        state = .edited
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private var hasUnsavedChanges: Bool {
        guard item != nil else { return hasText }
        return needsStoreSave || storedTitle != baselineTitle || storedContent != baselineContent
    }

    private var storedTitle: String {
        trimmedTitle.isEmpty ? Self.untitledTitle : trimmedTitle
    }

    private var storedContent: String? {
        trimmedContent.isEmpty ? nil : trimmedContent
    }

    /// Writes the draft now.
    ///
    /// - Parameter syncLinks: also turn typed `[[wiki links]]` into
    ///   connections. That reads every item, so it is for the moments a
    ///   writing session ends, not for each autosave.
    /// - Returns: the stored note, or nil when there is nothing to store or
    ///   the save failed.
    @discardableResult
    func save(syncLinks: Bool = false) -> Item? {
        saveTask?.cancel()
        saveTask = nil
        guard let modelContext, !isItemDeleted else { return nil }

        if let note = item {
            pullExternalChanges()
            let titleChanged = storedTitle != baselineTitle
            let contentChanged = storedContent != baselineContent
            if titleChanged || contentChanged || needsStoreSave {
                if titleChanged { note.title = storedTitle }
                if contentChanged { note.content = storedContent }
                if titleChanged || contentChanged { note.updatedAt = .now }
                baselineTitle = storedTitle
                baselineContent = storedContent
                do {
                    try modelContext.save()
                    needsStoreSave = false
                } catch {
                    needsStoreSave = true
                    state = .failed
                    return nil
                }
            }
            state = .saved
            if syncLinks { WikiLinkSync.sync(item: note, modelContext: modelContext) }
            return note
        }

        guard hasText else {
            state = .empty
            return nil
        }

        let note = Item(title: storedTitle, type: .note)
        note.status = .active
        note.content = storedContent
        note.updatedAt = .now
        modelContext.insert(note)
        if let boardID {
            let boards: [Board] = modelContext.fetchAll()
            if let board = boards.first(where: { $0.id == boardID }) {
                note.boards.append(board)
            }
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(note)
            state = .failed
            return nil
        }
        item = note
        createdItem = true
        baselineTitle = storedTitle
        baselineContent = storedContent
        state = .saved
        if syncLinks { WikiLinkSync.sync(item: note, modelContext: modelContext) }
        return note
    }

    /// Ends a writing session: saves, or — for a note this draft created that
    /// ended up with nothing in it — removes the empty note again.
    @discardableResult
    func finish() -> Item? {
        // Only a note that is truly blank: one that was given tags or links
        // through the inspector is kept even without text.
        if createdItem, !hasText, let note = item, !isItemDeleted, let modelContext,
           note.tags.isEmpty, note.outgoingConnections.isEmpty, note.incomingConnections.isEmpty {
            saveTask?.cancel()
            saveTask = nil
            item = nil
            state = .empty
            ItemViewModel(modelContext: modelContext).deleteItem(note)
            return nil
        }
        return save(syncLinks: true)
    }
}
