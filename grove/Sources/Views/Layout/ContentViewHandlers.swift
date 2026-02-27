import SwiftUI
import SwiftData

// MARK: - Content View Event Handlers

struct ContentViewEventHandlers: ViewModifier {
    @Bindable var viewModel: ContentViewModel
    let searchScopeBoard: Board?
    let boards: [Board]
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.selection) {
                viewModel.selectedItem = nil
                viewModel.openedItem = nil
                viewModel.inspectorUserOverride = nil
            }
            .onChange(of: viewModel.selectedItem) {
                viewModel.inspectorUserOverride = nil
            }
            .modifier(ContentViewNotificationHandlers(
                viewModel: viewModel,
                searchScopeBoard: searchScopeBoard,
                boards: boards,
                modelContext: modelContext
            ))
    }
}

struct ContentViewNotificationHandlers: ViewModifier {
    @Bindable var viewModel: ContentViewModel
    let searchScopeBoard: Board?
    let boards: [Board]
    let modelContext: ModelContext

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
                withAnimation { viewModel.inspectorUserOverride = !viewModel.isInspectorVisible }
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
                if viewModel.selectedItem != nil { viewModel.showItemExportSheet = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveToggleChat)) { _ in
                withAnimation { viewModel.showChatPanel.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveOpenConversation)) { notification in
                if let conversation = notification.object as? Conversation {
                    viewModel.selectedConversation = conversation
                    withAnimation { viewModel.showChatPanel = true }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveStartCheckIn)) { notification in
                guard let nudge = notification.object as? Nudge else { return }
                startCheckInConversation(from: nudge)
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
            .onReceive(NotificationCenter.default.publisher(for: .groveStartDialecticWithDisplayPrompt)) { notification in
                let prompt = notification.object as? String ?? ""
                startDialecticWithDisplayPrompt(prompt)
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
            .sheet(isPresented: $viewModel.showItemExportSheet) {
                if let item = viewModel.selectedItem {
                    ItemExportSheet(item: item)
                }
            }
            .onAppear {
                NudgeNotificationService.shared.configure()
                guard viewModel.nudgeEngine == nil else { return }
                let engine = NudgeEngine(modelContext: modelContext)
                engine.startSchedule()
                viewModel.nudgeEngine = engine
            }
            .onDisappear {
                viewModel.nudgeEngine?.stopSchedule()
                viewModel.nudgeEngine = nil
            }
    }

    private func openNudgeFromNotification(id: UUID) {
        let allNudges: [Nudge] = modelContext.fetchAll()
        guard let nudge = allNudges.first(where: { $0.id == id }),
              nudge.status == .pending || nudge.status == .shown
        else {
            NudgeNotificationService.shared.cancel(for: id)
            return
        }

        nudge.status = .actedOn
        NudgeSettings.recordAction(type: nudge.type, actedOn: true)
        NudgeNotificationService.shared.cancel(for: id)
        try? modelContext.save()

        switch nudge.type {
        case .resurface, .continueCourse, .reflectionPrompt, .contradiction,
             .knowledgeGap, .synthesisPrompt:
            guard let item = nudge.targetItem else { return }
            viewModel.selectedItem = item
            viewModel.openedItem = item
        case .staleInbox:
            viewModel.openedItem = nil
            viewModel.selectedItem = nil
            viewModel.selection = .library
        case .dialecticalCheckIn:
            startCheckInConversation(from: nudge)
        case .connectionPrompt, .streak:
            break
        }
    }

    private func dismissNudgeFromNotification(id: UUID) {
        let allNudges: [Nudge] = modelContext.fetchAll()
        guard let nudge = allNudges.first(where: { $0.id == id }),
              nudge.status == .pending || nudge.status == .shown
        else {
            NudgeNotificationService.shared.cancel(for: id)
            return
        }

        nudge.status = .dismissed
        NudgeSettings.recordAction(type: nudge.type, actedOn: false)
        NudgeNotificationService.shared.cancel(for: id)
        try? modelContext.save()
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

        var seedItems: [Item] = []
        if !seedItemIDs.isEmpty {
            let all: [Item] = modelContext.fetchAll()
            seedItems = all.filter { seedItemIDs.contains($0.id) }
        }
        let service = DialecticsService()
        let conversation = service.startConversation(
            trigger: .userInitiated,
            seedItems: seedItems,
            board: nil,
            context: modelContext
        )

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            switch injectionMode {
            case .asUserMessage:
                Task { @MainActor in
                    _ = await service.sendMessage(
                        userText: trimmedPrompt,
                        conversation: conversation,
                        context: modelContext
                    )
                }
            case .asSystemPrompt:
                let systemPromptMsg = ChatMessage(
                    role: .system,
                    content: trimmedPrompt,
                    position: conversation.nextPosition
                )
                systemPromptMsg.conversation = conversation
                conversation.messages.append(systemPromptMsg)
                modelContext.insert(systemPromptMsg)
                conversation.updatedAt = .now
                try? modelContext.save()
            case .asAssistantGreeting:
                let greetingMsg = ChatMessage(
                    role: .assistant,
                    content: trimmedPrompt,
                    position: conversation.nextPosition
                )
                greetingMsg.conversation = conversation
                conversation.messages.append(greetingMsg)
                modelContext.insert(greetingMsg)
                conversation.updatedAt = .now
                try? modelContext.save()
            }
        }

        viewModel.selectedConversation = conversation
        withAnimation { viewModel.showChatPanel = true }
    }

    private func startDiscussion(item: Item) {
        let service = DialecticsService()
        withAnimation { viewModel.showChatPanel = true }
        Task { @MainActor in
            let conversation = await service.startDiscussion(item: item, context: modelContext)
            viewModel.selectedConversation = conversation
        }
    }

    private func startCheckInConversation(from nudge: Nudge) {
        let trigger = nudge.checkInTrigger ?? .userInitiated
        let openingPrompt = nudge.checkInOpeningPrompt ?? ""
        let seedIDs = nudge.relatedItemIDs ?? []

        let allItems: [Item] = modelContext.fetchAll()
        let seedItems = seedIDs.compactMap { id in
            allItems.first(where: { $0.id == id })
        }

        let service = DialecticsService()
        let conversation = service.startConversation(
            trigger: trigger,
            seedItems: seedItems,
            board: nil,
            context: modelContext
        )

        if !openingPrompt.isEmpty {
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: openingPrompt,
                position: conversation.nextPosition
            )
            assistantMsg.conversation = conversation
            conversation.messages.append(assistantMsg)
            modelContext.insert(assistantMsg)
            conversation.updatedAt = .now
            try? modelContext.save()
        }

        viewModel.selectedConversation = conversation
        withAnimation { viewModel.showChatPanel = true }
    }

    private func startDialecticWithDisplayPrompt(_ prompt: String) {
        let service = DialecticsService()
        let conversation = service.startConversation(
            trigger: .userInitiated,
            seedItems: [],
            board: nil,
            context: modelContext
        )
        if !prompt.isEmpty {
            let assistantMsg = ChatMessage(
                role: .assistant,
                content: prompt,
                position: conversation.nextPosition
            )
            assistantMsg.conversation = conversation
            conversation.messages.append(assistantMsg)
            modelContext.insert(assistantMsg)
            conversation.updatedAt = .now
            try? modelContext.save()
        }
        viewModel.selectedConversation = conversation
        withAnimation { viewModel.showChatPanel = true }
    }
}
