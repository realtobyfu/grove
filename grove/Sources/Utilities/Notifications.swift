import Foundation
import SwiftData

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
    static let groveStartCheckIn = Notification.Name("groveStartCheckIn")
    static let groveEnterFocusMode = Notification.Name("groveEnterFocusMode")
    static let groveExitFocusMode = Notification.Name("groveExitFocusMode")
    /// Object: String — the writing prompt to display at the top of NoteWriterPanelView
    static let groveNewNoteWithPrompt = Notification.Name("groveNewNoteWithPrompt")
    static let groveStartConversationWithPrompt = Notification.Name("groveStartConversationWithPrompt")
    static let groveDiscussItem = Notification.Name("groveDiscussItem")
    static let groveStartDialecticWithDisplayPrompt = Notification.Name("groveStartDialecticWithDisplayPrompt")
    static let groveOpenReflectMode = Notification.Name("groveOpenReflectMode")
    static let groveOpenNudgeNotification = Notification.Name("groveOpenNudgeNotification")
    static let groveDismissNudgeNotification = Notification.Name("groveDismissNudgeNotification")
    /// Object: String — URL to pre-fill in the capture bar, then auto-capture
    static let groveCoachMarkPrefill = Notification.Name("groveCoachMarkPrefill")
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
}
