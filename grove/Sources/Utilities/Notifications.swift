import Foundation
import SwiftData

extension Notification.Name {
    static let groveNewNote = Notification.Name("groveNewNote")
    static let groveNewBoard = Notification.Name("groveNewBoard")
    /// Goes to the Library and focuses its find field, wherever the user is.
    /// ⌘⇧F and the sidebar's search field post it. ⌘F posts `groveFind`,
    /// which outside a reader opens the quick search overlay instead. On iOS
    /// the root views (`TabRootView`, `iPadRootView`) still answer it by
    /// opening their own search.
    static let groveToggleSearch = Notification.Name("groveToggleSearch")
    static let groveToggleInspector = Notification.Name("groveToggleInspector")
    static let groveCaptureBar = Notification.Name("groveCaptureBar")
    static let groveGoToHome = Notification.Name("groveGoToHome")
    static let groveGoToBoard = Notification.Name("groveGoToBoard")
    static let groveExportItem = Notification.Name("groveExportItem")
    static let groveToggleChat = Notification.Name("groveToggleChat")
    static let groveEnterFocusMode = Notification.Name("groveEnterFocusMode")
    static let groveExitFocusMode = Notification.Name("groveExitFocusMode")
    /// Object: String — the writing prompt to display at the top of NoteWriterPanelView
    static let groveNewNoteWithPrompt = Notification.Name("groveNewNoteWithPrompt")
    static let groveStartConversationWithPrompt = Notification.Name("groveStartConversationWithPrompt")
    static let groveDiscussItem = Notification.Name("groveDiscussItem")
    static let groveOpenReflectMode = Notification.Name("groveOpenReflectMode")
    /// Object: Bool — show (true) or put away (false) the open reader's own
    /// rail. Posted by the window when the Reflections tab is picked or the
    /// right page is closed; the reader owns that panel and its state.
    static let groveSetReaderRailVisible = Notification.Name("groveSetReaderRailVisible")
    /// ⌘F, from the menu. The menu does not know what is on screen, so it only
    /// asks: the window decides whether that means the open reader's find bar
    /// (`groveFindInArticle`) or library search (see
    /// `ContentViewModel.findShortcutTarget`).
    static let groveFind = Notification.Name("groveFind")
    /// Opens the find bar of the reader on screen and focuses its field.
    /// Posted by the window once it has routed `groveFind` to the reader.
    static let groveFindInArticle = Notification.Name("groveFindInArticle")
    /// ⌘G / ⌘⇧G: step to the next / previous match in the open reader.
    static let groveFindNext = Notification.Name("groveFindNext")
    static let groveFindPrevious = Notification.Name("groveFindPrevious")
    /// Reader text size, from the View menu. The reader routes these to whatever
    /// is on screen: the Reader-mode type scale, or page zoom on the live page.
    static let groveReaderTextLarger = Notification.Name("groveReaderTextLarger")
    static let groveReaderTextSmaller = Notification.Name("groveReaderTextSmaller")
    static let groveReaderTextReset = Notification.Name("groveReaderTextReset")
    /// Posted when a free user hits the dialectics monthly limit
    static let groveDialecticsLimitReached = Notification.Name("groveDialecticsLimitReached")
    /// Posted by `ItemViewModel.deleteItem(_:)` immediately *before* an Item is
    /// removed from the model context, so presentation layers can drop every
    /// reference to it while the model is still valid.
    /// userInfo["itemID"]: UUID — the id of the item about to be deleted.
    static let groveItemWillDelete = Notification.Name("groveItemWillDelete")
    /// Object: UUID — open an existing item in the reader. Posted by surfaces
    /// that hold no navigation state of their own (capture bar duplicates).
    static let groveOpenItem = Notification.Name("groveOpenItem")
}

// MARK: - Typed Notification Payloads

struct ConversationPromptPayload {
    let prompt: String
    let seedItemIDs: [UUID]
    let injectionMode: ConversationPromptInjectionMode

    init(
        prompt: String,
        seedItemIDs: [UUID] = [],
        injectionMode: ConversationPromptInjectionMode = .asUserMessage
    ) {
        self.prompt = prompt
        self.seedItemIDs = seedItemIDs
        self.injectionMode = injectionMode
    }
}

struct DiscussItemPayload {
    let item: Item
}

enum ConversationPromptInjectionMode: String {
    case asUserMessage
    case asSystemPrompt
    case asAssistantGreeting
}

extension NotificationCenter {
    func postConversationPrompt(_ payload: ConversationPromptPayload) {
        var userInfo: [String: Any] = [:]
        if !payload.seedItemIDs.isEmpty {
            userInfo["seedItemIDs"] = payload.seedItemIDs
        }
        userInfo["injectionMode"] = payload.injectionMode.rawValue
        post(
            name: .groveStartConversationWithPrompt,
            object: payload.prompt,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }

    static func conversationPromptPayload(from notification: Notification) -> ConversationPromptPayload {
        let prompt = notification.object as? String ?? ""
        let seedIDs = notification.userInfo?["seedItemIDs"] as? [UUID] ?? []
        let injectionModeRaw = notification.userInfo?["injectionMode"] as? String
        let injectionMode = injectionModeRaw
            .flatMap(ConversationPromptInjectionMode.init(rawValue:))
            ?? .asUserMessage
        return ConversationPromptPayload(
            prompt: prompt,
            seedItemIDs: seedIDs,
            injectionMode: injectionMode
        )
    }

    func postDiscussItem(_ payload: DiscussItemPayload) {
        post(name: .groveDiscussItem, object: payload.item)
    }

    static func discussItemPayload(from notification: Notification) -> DiscussItemPayload? {
        guard let item = notification.object as? Item else { return nil }
        return DiscussItemPayload(item: item)
    }

    /// Announce an imminent Item deletion. Carries only the id — observers must
    /// not retain the model itself, since it is about to become invalid.
    func postItemWillDelete(id: UUID) {
        post(name: .groveItemWillDelete, object: nil, userInfo: ["itemID": id])
    }

    static func itemWillDeleteID(from notification: Notification) -> UUID? {
        notification.userInfo?["itemID"] as? UUID
    }
}
