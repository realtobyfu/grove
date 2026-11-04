import SQLiteData
import SwiftUI

// MARK: - Content View Event Handlers

struct ContentViewEventHandlers: ViewModifier {
    @Bindable var viewModel: ContentViewModel
    let searchScopeBoard: BoardGraph?
    let boards: [BoardGraph]

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.selection) {
                viewModel.selectedItem = nil
                viewModel.openedItem = nil
                viewModel.inspectorUserOverride = nil
            }
            .onChange(of: viewModel.selectedItem?.id) {
                viewModel.inspectorUserOverride = nil
            }
            .modifier(ContentViewNotificationHandlers(
                viewModel: viewModel,
                searchScopeBoard: searchScopeBoard,
                boards: boards
            ))
    }
}

struct ContentViewNotificationHandlers: ViewModifier {
    @Bindable var viewModel: ContentViewModel
    let searchScopeBoard: BoardGraph?
    let boards: [BoardGraph]
    @Dependency(\.defaultDatabase) private var database

    func body(content: Content) -> some View {
        let step1 = content
            .onReceive(NotificationCenter.default.publisher(for: .groveNewNote)) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.writePanelPrompt = nil
                    viewModel.showWritePanel = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveNewNoteWithPrompt)) { notification in
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.writePanelPrompt = notification.object as? String
                    viewModel.showWritePanel = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveToggleSearch)) { _ in
                if viewModel.isArticleWebViewActive {
                    NotificationCenter.default.post(name: .groveFindInArticle, object: nil)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if !viewModel.showSearch { viewModel.showCaptureOverlay = false }
                        viewModel.showSearch.toggle()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveToggleInspector)) { _ in
                withAnimation(RightRailMetrics.widthChange) {
                    viewModel.inspectorUserOverride = !viewModel.isInspectorVisible
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveCaptureBar)) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if !viewModel.showCaptureOverlay { viewModel.showSearch = false }
                    viewModel.showCaptureOverlay.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveGoToHome)) { _ in
                viewModel.selection = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveGoToBoard)) { notification in
                if let index = notification.object as? Int, index >= 1, index <= boards.count {
                    viewModel.selection = .board(boards[index - 1].id)
                }
            }
        return step1
            .onReceive(NotificationCenter.default.publisher(for: .groveExportItem)) { _ in
                guard let item = viewModel.selectedItem else { return }
                // Deferred a turn: NSSavePanel.runModal() spins a nested run
                // loop, which must not be entered from inside notification
                // delivery mid-SwiftUI-update.
                Task { @MainActor in
                    ItemExportAction.exportAsMarkdown(item)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveItemWillDelete)) { notification in
                guard let id = NotificationCenter.itemWillDeleteID(from: notification) else { return }
                clearPresentationState(forDeletedItemID: id)
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveOpenItem)) { notification in
                guard let id = notification.object as? UUID else { return }
                openItem(id: id)
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveToggleChat)) { _ in
                withAnimation(RightRailMetrics.widthChange) { viewModel.showChatPanel.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveOpenConversation)) { notification in
                if let conversation = notification.object as? ConversationGraph {
                    viewModel.selectedConversation = conversation
                    withAnimation(RightRailMetrics.widthChange) { viewModel.showChatPanel = true }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveStartConversationWithPrompt)) { notification in
                let payload = NotificationCenter.conversationPromptPayload(from: notification)
                startConversation(
                    withPrompt: payload.prompt,
                    seedItemIDs: payload.seedItemIDs,
                    injectionMode: payload.injectionMode
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveDiscussItem)) { notification in
                guard let payload = NotificationCenter.discussItemPayload(from: notification) else { return }
                startDiscussion(item: payload.item)
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveOpenNudgeNotification)) { notification in
                guard let nudgeID = notification.object as? UUID else { return }
                openNudgeFromNotification(id: nudgeID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveDismissNudgeNotification)) { notification in
                guard let nudgeID = notification.object as? UUID else { return }
                dismissNudgeFromNotification(id: nudgeID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveEnterFocusMode)) { _ in
                viewModel.enterFocusMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveExitFocusMode)) { _ in
                viewModel.exitFocusMode()
            }
            .onAppear {
                NudgeNotificationService.shared.configure()
                guard viewModel.nudgeEngine == nil else { return }
                let engine = NudgeEngine()
                engine.startSchedule()
                viewModel.nudgeEngine = engine
            }
            .onDisappear {
                viewModel.nudgeEngine?.stopSchedule()
                viewModel.nudgeEngine = nil
            }
    }

    /// Drop every reference to an item that is about to be deleted.
    ///
    /// `writePanelEditItem` is the load-bearing one: opening a note nils
    /// `openedItem` right after handing the item to the write panel, so an
    /// id-match against `openedItem` alone never fires and the panel would keep
    /// rendering — and on dismiss, keep saving — a deleted item.
    private func clearPresentationState(forDeletedItemID id: UUID) {
        if viewModel.writePanelEditItem?.id == id {
            viewModel.writePanelEditItem = nil
            viewModel.showWritePanel = false
        }
        if viewModel.selectedItem?.id == id {
            viewModel.selectedItem = nil
        }
        if viewModel.openedItem?.id == id {
            viewModel.openedItem = nil
        }
    }

    /// Open an item by id — the app-wide answer to "show me that one".
    /// Used by the capture bar when a paste turns out to be a duplicate.
    private func openItem(id: UUID) {
        guard let item = fetchItem(id) else { return }
        viewModel.showCaptureOverlay = false
        viewModel.selectedItem = item
        viewModel.openedItem = item
    }

    private func fetchItem(_ id: Item.ID) -> ItemGraph? {
        database.attemptRead { try ItemGraph.fetch(id, in: $0) } ?? nil
    }

    private func fetchNudge(_ id: Nudge.ID) -> Nudge? {
        database.attemptRead { try Nudge.find(id).fetchOne($0) } ?? nil
    }

    private func openNudgeFromNotification(id: UUID) {
        guard let nudge = fetchNudge(id),
              nudge.status == .pending || nudge.status == .shown
        else {
            NudgeNotificationService.shared.cancel(for: id)
            return
        }

        database.attempt { db in
            try Nudge.modify(id, in: db) { $0.status = .actedOn }
        }
        NudgeSettings.recordAction(type: nudge.type, actedOn: true)
        NudgeNotificationService.shared.cancel(for: id)

        switch nudge.type {
        case .staleInbox:
            viewModel.openedItem = nil
            viewModel.selectedItem = nil
            viewModel.selection = .library
        default:
            // Resurface plus legacy types retained only for persisted records.
            guard let targetID = nudge.targetItemID, let item = fetchItem(targetID) else { return }
            viewModel.selectedItem = item
            viewModel.openedItem = item
        }
    }

    private func dismissNudgeFromNotification(id: UUID) {
        guard let nudge = fetchNudge(id),
              nudge.status == .pending || nudge.status == .shown
        else {
            NudgeNotificationService.shared.cancel(for: id)
            return
        }

        database.attempt { db in
            try Nudge.modify(id, in: db) { $0.status = .dismissed }
        }
        NudgeSettings.recordAction(type: nudge.type, actedOn: false)
        NudgeNotificationService.shared.cancel(for: id)
    }

    private func startConversation(
        withPrompt prompt: String,
        seedItemIDs: [UUID] = [],
        injectionMode: ConversationPromptInjectionMode = .asUserMessage
    ) {
        let entitlement = EntitlementService.shared
        guard entitlement.canUse(.dialectics) else {
            // Post paywall presentation via notification -- the sheet binding is on DialecticalChatPanel
            NotificationCenter.default.post(name: .groveDialecticsLimitReached, object: nil)
            return
        }
        entitlement.recordUse(.dialectics)

        var seedItems: [ItemGraph] = []
        if !seedItemIDs.isEmpty {
            let all = database.attemptRead { try Library.fetch($0).items } ?? []
            seedItems = all.filter { seedItemIDs.contains($0.id) }
        }
        let service = DialecticsService()
        let conversation = service.startConversation(
            trigger: .userInitiated,
            seedItems: seedItems,
            board: nil
        )

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            switch injectionMode {
            case .asUserMessage:
                Task { @MainActor in
                    _ = await service.sendMessage(
                        userText: trimmedPrompt,
                        conversationID: conversation.id
                    )
                }
            case .asSystemPrompt:
                service.appendMessage(role: .system, content: trimmedPrompt, to: conversation.id)
            case .asAssistantGreeting:
                service.appendMessage(role: .assistant, content: trimmedPrompt, to: conversation.id)
            }
        }

        viewModel.selectedConversation = conversation
        withAnimation(RightRailMetrics.widthChange) { viewModel.showChatPanel = true }
    }

    private func startDiscussion(item: ItemGraph) {
        let service = DialecticsService()
        withAnimation(RightRailMetrics.widthChange) { viewModel.showChatPanel = true }
        Task { @MainActor in
            let conversation = await service.startDiscussion(item: item)
            viewModel.selectedConversation = conversation
        }
    }

}
