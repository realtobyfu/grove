import Foundation
import SwiftData
import SwiftUI

/// ViewModel that owns all business state for the Dialectics chat panel.
/// Pure UI state (scroll position, focus) stays in the view.
@MainActor
@Observable
final class DialecticalChatViewModel {
    // MARK: - Dependencies

    private(set) var dialecticsService = DialecticsService()
    private var modelContext: ModelContext

    // MARK: - Business State

    var inputText = ""
    var connectionMessage: ChatMessage?
    var connectionType: ConnectionType = .related
    var reflectionMessage: ChatMessage?
    var reflectionConversation: Conversation?
    var noteMessage: ChatMessage?
    var conversationToDelete: Conversation?
    var conversationListQuery = ""
    var conversationListSelectionID: UUID?
    var paywallPresentation: PaywallPresentation?
    var showConversationList = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Update the model context (e.g. when Environment changes).
    func updateModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Computed Properties

    func activeConversations(from conversations: [Conversation]) -> [Conversation] {
        conversations.filter { !$0.isArchived }
    }

    func visibleHistoryConversations(
        from conversations: [Conversation],
        entitlement: EntitlementService
    ) -> [Conversation] {
        let active = activeConversations(from: conversations)
        guard entitlement.hasAccess(to: .fullHistory) else {
            return Array(active.prefix(20))
        }
        return active
    }

    func isHistoryCapped(
        conversations: [Conversation],
        entitlement: EntitlementService
    ) -> Bool {
        let active = activeConversations(from: conversations)
        let visible = visibleHistoryConversations(from: conversations, entitlement: entitlement)
        return !entitlement.hasAccess(to: .fullHistory) && active.count > visible.count
    }

    var trimmedConversationListQuery: String {
        conversationListQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func filteredConversations(
        from conversations: [Conversation],
        entitlement: EntitlementService
    ) -> [Conversation] {
        let visible = visibleHistoryConversations(from: conversations, entitlement: entitlement)
        let query = trimmedConversationListQuery
        guard !query.isEmpty else { return visible }
        return visible.filter { conversationMatchesSearch($0, query: query) }
    }

    func filteredConversationIDs(
        from conversations: [Conversation],
        entitlement: EntitlementService
    ) -> [UUID] {
        filteredConversations(from: conversations, entitlement: entitlement).map(\.id)
    }

    // MARK: - Conversation CRUD

    func startNewConversation(
        selectedConversation: Binding<Conversation?>,
        currentBoard: Board?,
        entitlement: EntitlementService,
        paywallCoordinator: PaywallCoordinator
    ) {
        guard entitlement.canUse(.dialectics) else {
            paywallPresentation = paywallCoordinator.present(
                feature: .dialectics,
                source: .dialecticsLimit
            )
            return
        }
        entitlement.recordUse(.dialectics)

        let seedItems: [Item]
        if let board = currentBoard {
            seedItems = Array(
                board.items
                    .filter { $0.status == .active }
                    .sorted { $0.depthScore > $1.depthScore }
                    .prefix(10)
            )
        } else {
            seedItems = []
        }
        let conversation = dialecticsService.startConversation(
            trigger: .userInitiated,
            seedItems: seedItems,
            board: currentBoard,
            context: modelContext
        )
        selectedConversation.wrappedValue = conversation
    }

    func sendMessage(to conversation: Conversation) {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""

        Task {
            _ = await dialecticsService.sendMessage(
                userText: text,
                conversation: conversation,
                context: modelContext
            )
        }
    }

    func deleteConversation(
        _ conversation: Conversation,
        selectedConversation: Binding<Conversation?>,
        conversations: [Conversation]
    ) {
        let active = activeConversations(from: conversations)
        let nextConversation = active.first { $0.id != conversation.id }
        if selectedConversation.wrappedValue?.id == conversation.id {
            selectedConversation.wrappedValue = nextConversation
        }
        modelContext.delete(conversation)
        try? modelContext.save()
        conversationToDelete = nil
    }

    // MARK: - Connection Creation

    func createConnection(
        from message: ChatMessage,
        type: ConnectionType
    ) {
        let allItems: [Item] = modelContext.fetchAll()
        let referenced = message.referencedItemIDs.compactMap { id in
            allItems.first(where: { $0.id == id })
        }
        guard referenced.count >= 2 else { return }

        _ = dialecticsService.createConnection(
            sourceTitle: referenced[0].title,
            targetTitle: referenced[1].title,
            type: type,
            context: modelContext
        )
        connectionMessage = nil
    }

    func referencedItems(for message: ChatMessage) -> [Item] {
        let allItems: [Item] = modelContext.fetchAll()
        return message.referencedItemIDs.compactMap { id in
            allItems.first(where: { $0.id == id })
        }
    }

    // MARK: - Search & Navigation

    func conversationMatchesSearch(_ conversation: Conversation, query: String) -> Bool {
        if conversation.displayTitle.localizedStandardContains(query) {
            return true
        }
        return conversation.visibleMessages.contains { message in
            message.content.localizedStandardContains(query)
        }
    }

    func navigateToItemByTitle(_ title: String, onNavigateToItem: ((Item) -> Void)?) {
        let allItems: [Item] = modelContext.fetchAll()
        if let item = allItems.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
            onNavigateToItem?(item)
        }
    }

    func seedItems(for conversation: Conversation) -> [Item] {
        let allItems: [Item] = modelContext.fetchAll()
        return conversation.seedItemIDs.compactMap { id in
            allItems.first(where: { $0.id == id })
        }
    }

    // MARK: - Conversation List Popover Logic

    func prepareConversationListPopover(selectedConversation: Conversation?) {
        conversationListQuery = ""
        syncConversationListSelection(
            preferredID: selectedConversation?.id,
            conversations: []  // Will be re-synced on onChange
        )
    }

    func syncConversationListSelection(
        preferredID: UUID? = nil,
        conversations: [Conversation],
        selectedConversation: Conversation? = nil
    ) {
        guard !conversations.isEmpty else {
            conversationListSelectionID = nil
            return
        }

        if let preferredID, conversations.contains(where: { $0.id == preferredID }) {
            conversationListSelectionID = preferredID
            return
        }

        if let currentID = conversationListSelectionID, conversations.contains(where: { $0.id == currentID }) {
            return
        }

        if let selectedID = selectedConversation?.id, conversations.contains(where: { $0.id == selectedID }) {
            conversationListSelectionID = selectedID
            return
        }

        conversationListSelectionID = conversations.first?.id
    }

    func moveConversationListSelection(
        offset: Int,
        filteredIDs: [UUID]
    ) {
        guard !filteredIDs.isEmpty else {
            conversationListSelectionID = nil
            return
        }

        guard let currentID = conversationListSelectionID,
              let currentIndex = filteredIDs.firstIndex(of: currentID) else {
            conversationListSelectionID = filteredIDs.first
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), filteredIDs.count - 1)
        conversationListSelectionID = filteredIDs[nextIndex]
    }

    func openConversationFromList(
        _ conversation: Conversation,
        selectedConversation: Binding<Conversation?>
    ) {
        selectedConversation.wrappedValue = conversation
        showConversationList = false
    }

    func openSelectedConversationFromList(
        filteredConversations: [Conversation],
        selectedConversation: Binding<Conversation?>
    ) {
        guard let selectedID = conversationListSelectionID,
              let conversation = filteredConversations.first(where: { $0.id == selectedID }) else { return }
        openConversationFromList(conversation, selectedConversation: selectedConversation)
    }
}
