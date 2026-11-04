import Foundation
import SQLiteData
import SwiftUI

/// ViewModel that owns all business state for the Dialectics chat panel.
/// Pure UI state (scroll position, focus) stays in the view.
@MainActor
@Observable
final class DialecticalChatViewModel {
    // MARK: - Dependencies

    private(set) var dialecticsService: DialecticsService
    private let database: any DatabaseWriter

    // MARK: - Business State

    /// The conversation on screen, as of the last reload. A `ConversationGraph`
    /// is a value, so the selection the view holds stops growing the moment it's
    /// picked. This is what the chat shows instead: see `current(_:)`.
    private(set) var conversation: ConversationGraph?
    var inputText = ""
    var connectionMessage: ChatMessage?
    var connectionType: ConnectionType = .related
    var reflectionMessage: ChatMessage?
    var reflectionConversation: ConversationGraph?
    var noteMessage: ChatMessage?
    var conversationToDelete: ConversationGraph?
    var conversationListQuery = ""
    var conversationListSelectionID: UUID?
    var paywallPresentation: PaywallPresentation?
    var showConversationList = false

    init(database: any DatabaseWriter = AppDatabase.current) {
        self.database = database
        dialecticsService = DialecticsService(database: database)
        // Reloading on every write is what shows a sent message at once, without
        // waiting for the reply the service is about to spend seconds on.
        dialecticsService.onConversationChanged = { [weak self] conversationID in
            guard let self, conversation?.id == conversationID else { return }
            loadConversation(conversationID)
        }
    }

    // MARK: - Current Conversation

    /// Reads the conversation to show, or clears it for `nil`.
    ///
    /// Writes through `dialecticsService` reload it without help. The panel calls
    /// this when its selection changes, and again when its `conversations` change,
    /// because other writers can't reach this view model: a prompt or discussion
    /// started from elsewhere runs on its own `DialecticsService`, and sync
    /// arrives on its own.
    func loadConversation(_ conversationID: Conversation.ID?) {
        conversation = conversationID.flatMap { id in
            database.attemptRead { try ConversationGraph.fetch(id, in: $0) } ?? nil
        }
    }

    /// The freshest copy of the view's selection: the one loaded here, or the
    /// selection itself in the moment before `loadConversation` catches up with it.
    func current(_ selected: ConversationGraph?) -> ConversationGraph? {
        guard let selected else { return nil }
        return conversation?.id == selected.id ? conversation : selected
    }

    // MARK: - Computed Properties

    func activeConversations(from conversations: [ConversationGraph]) -> [ConversationGraph] {
        conversations.filter { !$0.isArchived && $0.isSavedToHistory }
    }

    func visibleHistoryConversations(
        from conversations: [ConversationGraph],
        entitlement: EntitlementService
    ) -> [ConversationGraph] {
        let active = activeConversations(from: conversations)
        guard entitlement.hasAccess(to: .fullHistory) else {
            return Array(active.prefix(20))
        }
        return active
    }

    func isHistoryCapped(
        conversations: [ConversationGraph],
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
        from conversations: [ConversationGraph],
        entitlement: EntitlementService
    ) -> [ConversationGraph] {
        let visible = visibleHistoryConversations(from: conversations, entitlement: entitlement)
        let query = trimmedConversationListQuery
        guard !query.isEmpty else { return visible }
        return visible.filter { conversationMatchesSearch($0, query: query) }
    }

    func filteredConversationIDs(
        from conversations: [ConversationGraph],
        entitlement: EntitlementService
    ) -> [UUID] {
        filteredConversations(from: conversations, entitlement: entitlement).map(\.id)
    }

    // MARK: - Conversation CRUD

    func startNewConversation(
        selectedConversation: Binding<ConversationGraph?>,
        currentBoard: BoardGraph?,
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

        let seedItems: [ItemGraph]
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
            board: currentBoard?.board
        )
        selectedConversation.wrappedValue = conversation
    }

    func sendMessage(to conversationID: Conversation.ID) {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""

        Task {
            _ = await dialecticsService.sendMessage(
                userText: text,
                conversationID: conversationID
            )
        }
    }

    func deleteConversation(
        _ conversationID: Conversation.ID,
        selectedConversation: Binding<ConversationGraph?>,
        conversations: [ConversationGraph]
    ) {
        let active = activeConversations(from: conversations)
        let nextConversation = active.first { $0.id != conversationID }
        if selectedConversation.wrappedValue?.id == conversationID {
            selectedConversation.wrappedValue = nextConversation
        }
        database.attempt { db in
            try Conversation.find(conversationID).delete().execute(db)
        }
        conversationToDelete = nil
    }

    // MARK: - Connection Creation

    func createConnection(
        from message: ChatMessage,
        type: ConnectionType
    ) {
        let referenced = referencedItems(for: message)
        guard referenced.count >= 2 else { return }

        _ = dialecticsService.createConnection(
            sourceTitle: referenced[0].title,
            targetTitle: referenced[1].title,
            type: type
        )
        connectionMessage = nil
    }

    func referencedItems(for message: ChatMessage) -> [ItemGraph] {
        fetchItems(message.referencedItemIDs)
    }

    /// Reads these items and no others, in this order. Views call this while
    /// rendering, the chat input on every keystroke, so loading the whole
    /// library here would be felt.
    private func fetchItems(_ itemIDs: [Item.ID]) -> [ItemGraph] {
        database.attemptRead { db in
            try itemIDs.compactMap { try ItemGraph.fetch($0, in: db) }
        } ?? []
    }

    // MARK: - Search & Navigation

    func conversationMatchesSearch(_ conversation: ConversationGraph, query: String) -> Bool {
        if conversation.displayTitle.localizedStandardContains(query) {
            return true
        }
        return conversation.visibleMessages.contains { message in
            message.content.localizedStandardContains(query)
        }
    }

    func navigateToItemByTitle(_ title: String, onNavigateToItem: ((ItemGraph) -> Void)?) {
        let allItems = database.attemptRead { try Library.fetch($0).items } ?? []
        if let item = ItemResolver.resolveExactTitle(title, in: allItems) {
            onNavigateToItem?(item)
        }
    }

    func seedItems(for conversation: ConversationGraph) -> [ItemGraph] {
        fetchItems(conversation.seedItemIDs)
    }

    // MARK: - Conversation List Popover Logic

    func prepareConversationListPopover(selectedConversation: ConversationGraph?) {
        conversationListQuery = ""
        syncConversationListSelection(
            preferredID: selectedConversation?.id,
            conversations: []  // Will be re-synced on onChange
        )
    }

    func syncConversationListSelection(
        preferredID: UUID? = nil,
        conversations: [ConversationGraph],
        selectedConversation: ConversationGraph? = nil
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
        _ conversation: ConversationGraph,
        selectedConversation: Binding<ConversationGraph?>
    ) {
        selectedConversation.wrappedValue = conversation
        showConversationList = false
    }

    func openSelectedConversationFromList(
        filteredConversations: [ConversationGraph],
        selectedConversation: Binding<ConversationGraph?>
    ) {
        guard let selectedID = conversationListSelectionID,
              let conversation = filteredConversations.first(where: { $0.id == selectedID }) else { return }
        openConversationFromList(conversation, selectedConversation: selectedConversation)
    }
}
