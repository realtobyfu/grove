import Foundation

extension Notification.Name {
    static let groveNewNote = Notification.Name("groveNewNote")
    static let groveNewBoard = Notification.Name("groveNewBoard")
    static let groveToggleSearch = Notification.Name("groveToggleSearch")
    static let groveToggleInspector = Notification.Name("groveToggleInspector")
    static let groveCaptureBar = Notification.Name("groveCaptureBar")
    static let groveGoToHome = Notification.Name("groveGoToHome")
    static let groveGoToBoard = Notification.Name("groveGoToBoard")
    static let groveGoToTags = Notification.Name("groveGoToTags")
    static let groveExportItem = Notification.Name("groveExportItem")
    static let groveToggleChat = Notification.Name("groveToggleChat")
    static let groveOpenConversation = Notification.Name("groveOpenConversation")
    static let groveEnterFocusMode = Notification.Name("groveEnterFocusMode")
    static let groveExitFocusMode = Notification.Name("groveExitFocusMode")
    /// Object: String — the writing prompt to display at the top of NoteWriterPanelView
    static let groveNewNoteWithPrompt = Notification.Name("groveNewNoteWithPrompt")
    static let groveStartConversationWithPrompt = Notification.Name("groveStartConversationWithPrompt")
    static let groveDiscussItem = Notification.Name("groveDiscussItem")
    static let groveOpenReflectMode = Notification.Name("groveOpenReflectMode")
    static let groveOpenNudgeNotification = Notification.Name("groveOpenNudgeNotification")
    static let groveDismissNudgeNotification = Notification.Name("groveDismissNudgeNotification")
    /// Object: String — URL to pre-fill in the capture bar, then auto-capture
    static let groveCoachMarkPrefill = Notification.Name("groveCoachMarkPrefill")
    /// Posted to trigger find-in-page when an article WebView is active
    static let groveFindInArticle = Notification.Name("groveFindInArticle")
    /// Reader text size, from the View menu. The reader routes these to whatever
    /// is on screen: the Reader-mode type scale, or page zoom on the live page.
    static let groveReaderTextLarger = Notification.Name("groveReaderTextLarger")
    static let groveReaderTextSmaller = Notification.Name("groveReaderTextSmaller")
    static let groveReaderTextReset = Notification.Name("groveReaderTextReset")
    /// Posted when a free user hits the dialectics monthly limit
    static let groveDialecticsLimitReached = Notification.Name("groveDialecticsLimitReached")
    /// Posted by `ItemViewModel.deleteItem(_:)` immediately *before* an Item is
    /// deleted from the database, so presentation layers can drop every
    /// reference to it while the row still exists.
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
    let item: ItemGraph
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
        guard let item = notification.object as? ItemGraph else { return nil }
        return DiscussItemPayload(item: item)
    }

    /// Announce an imminent Item deletion. Carries only the id — observers must
    /// not hold on to the item itself, since its row is about to go.
    func postItemWillDelete(id: UUID) {
        post(name: .groveItemWillDelete, object: nil, userInfo: ["itemID": id])
    }

    static func itemWillDeleteID(from notification: Notification) -> UUID? {
        notification.userInfo?["itemID"] as? UUID
    }
}
