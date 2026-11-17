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
            state = .saved
        }
    }

    /// Call when the title or the body changes.
    func textDidChange() {
        guard isConfigured, !isItemDeleted else { return }
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
        guard let item else { return hasText }
        return item.title != storedTitle || item.content != storedContent
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
            if note.title != storedTitle || note.content != storedContent {
                note.title = storedTitle
                note.content = storedContent
                note.updatedAt = .now
                do {
                    try modelContext.save()
                } catch {
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
        state = .saved
        if syncLinks { WikiLinkSync.sync(item: note, modelContext: modelContext) }
        return note
    }

    /// Ends a writing session: saves, or — for a note this draft created that
    /// ended up with nothing in it — removes the empty note again.
    @discardableResult
    func finish() -> Item? {
        if createdItem, !hasText, let note = item, !isItemDeleted, let modelContext {
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
