import Foundation

extension Notification.Name {
    static let groveNewNote = Notification.Name("groveNewNote")
    static let groveQuickCapture = Notification.Name("groveQuickCapture")
    static let groveToggleSearch = Notification.Name("groveToggleSearch")
    static let groveToggleInspector = Notification.Name("groveToggleInspector")
    static let groveCaptureBar = Notification.Name("groveCaptureBar")
    static let groveGoToHome = Notification.Name("groveGoToHome")
    static let groveGoToBoard = Notification.Name("groveGoToBoard")
    static let groveGoToTags = Notification.Name("groveGoToTags")
    static let groveExportBoard = Notification.Name("groveExportBoard")
    static let groveExportItem = Notification.Name("groveExportItem")
    static let groveToggleChat = Notification.Name("groveToggleChat")
    static let groveOpenConversation = Notification.Name("groveOpenConversation")
    static let groveStartCheckIn = Notification.Name("groveStartCheckIn")
    static let groveEnterFocusMode = Notification.Name("groveEnterFocusMode")
    static let groveExitFocusMode = Notification.Name("groveExitFocusMode")
    /// Object: String — the prompt text to pre-fill as the first user message
    /// userInfo["seedItemIDs"]: [UUID] — optional item IDs to seed the conversation context
    static let groveStartConversationWithPrompt = Notification.Name("groveStartConversationWithPrompt")
    /// Object: Item — the item to anchor the conversation to; opens Dialectics with a pre-generated opening message
    static let groveDiscussItem = Notification.Name("groveDiscussItem")
}
