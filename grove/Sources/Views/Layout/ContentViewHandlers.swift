import SwiftUI
import SwiftData

// MARK: - Content View Event Handlers

struct ContentViewEventHandlers: ViewModifier {
    @Binding var selection: SidebarItem?
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Binding var showWritePanel: Bool
    @Binding var writePanelPrompt: String?
    @Binding var showSearch: Bool
    @Binding var showCaptureOverlay: Bool
    @Binding var showItemExportSheet: Bool
    @Binding var showChatPanel: Bool
    @Binding var selectedConversation: Conversation?
    @Binding var inspectorUserOverride: Bool?
    @Binding var nudgeEngine: NudgeEngine?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var savedColumnVisibility: NavigationSplitViewVisibility?
    @Binding var savedInspectorOverride: Bool?
    @Binding var savedChatPanel: Bool?
    let isInspectorVisible: Bool
    let searchScopeBoard: Board?
    let boards: [Board]
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            .onChange(of: selection) {
                selectedItem = nil
                openedItem = nil
                inspectorUserOverride = nil
            }
            .onChange(of: selectedItem) {
                inspectorUserOverride = nil
            }
            .modifier(ContentViewNotificationHandlers(
                showWritePanel: $showWritePanel,
                writePanelPrompt: $writePanelPrompt,
                showSearch: $showSearch,
                showCaptureOverlay: $showCaptureOverlay,
                showItemExportSheet: $showItemExportSheet,
                showChatPanel: $showChatPanel,
                selectedConversation: $selectedConversation,
                inspectorUserOverride: $inspectorUserOverride,
                selection: $selection,
                selectedItem: $selectedItem,
                openedItem: $openedItem,
                nudgeEngine: $nudgeEngine,
                columnVisibility: $columnVisibility,
                savedColumnVisibility: $savedColumnVisibility,
                savedInspectorOverride: $savedInspectorOverride,
                savedChatPanel: $savedChatPanel,
                isInspectorVisible: isInspectorVisible,
                searchScopeBoard: searchScopeBoard,
                boards: boards,
                modelContext: modelContext
            ))
    }
}

struct ContentViewNotificationHandlers: ViewModifier {
    @Binding var showWritePanel: Bool
    @Binding var writePanelPrompt: String?
    @Binding var showSearch: Bool
    @Binding var showCaptureOverlay: Bool
    @Binding var showItemExportSheet: Bool
    @Binding var showChatPanel: Bool
    @Binding var selectedConversation: Conversation?
    @Binding var inspectorUserOverride: Bool?
    @Binding var selection: SidebarItem?
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Binding var nudgeEngine: NudgeEngine?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var savedColumnVisibility: NavigationSplitViewVisibility?
    @Binding var savedInspectorOverride: Bool?
    @Binding var savedChatPanel: Bool?
    let isInspectorVisible: Bool
    let searchScopeBoard: Board?
    let boards: [Board]
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        let step1 = content
            .onReceive(NotificationCenter.default.publisher(for: .groveNewNote)) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    writePanelPrompt = nil
                    showWritePanel = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveNewNoteWithPrompt)) { notification in
                withAnimation(.easeOut(duration: 0.2)) {
                    writePanelPrompt = notification.object as? String
                    showWritePanel = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveToggleSearch)) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if !showSearch { showCaptureOverlay = false }
                    showSearch.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveToggleInspector)) { _ in
                withAnimation { inspectorUserOverride = !isInspectorVisible }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveCaptureBar)) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if !showCaptureOverlay { showSearch = false }
                    showCaptureOverlay.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveGoToHome)) { _ in
                selection = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveGoToBoard)) { notification in
                if let index = notification.object as? Int, index >= 1, index <= boards.count {
                    selection = .board(boards[index - 1].id)
                }
            }
        return step1
            .onReceive(NotificationCenter.default.publisher(for: .groveExportItem)) { _ in
                if selectedItem != nil { showItemExportSheet = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveToggleChat)) { _ in
                withAnimation { showChatPanel.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveOpenConversation)) { notification in
                if let conversation = notification.object as? Conversation {
                    selectedConversation = conversation
                    withAnimation { showChatPanel = true }
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
                savedColumnVisibility = columnVisibility
                savedInspectorOverride = inspectorUserOverride
                savedChatPanel = showChatPanel
                withAnimation(.easeOut(duration: 0.25)) {
                    columnVisibility = .detailOnly
                    inspectorUserOverride = false
                    showChatPanel = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveExitFocusMode)) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    columnVisibility = savedColumnVisibility ?? .automatic
                    inspectorUserOverride = savedInspectorOverride
                    showChatPanel = savedChatPanel ?? false
                }
                savedColumnVisibility = nil
                savedInspectorOverride = nil
                savedChatPanel = nil
            }
            .sheet(isPresented: $showItemExportSheet) {
                if let item = selectedItem {
                    ItemExportSheet(item: item)
                }
            }
            .onAppear {
                NudgeNotificationService.shared.configure()
                guard nudgeEngine == nil else { return }
                let engine = NudgeEngine(modelContext: modelContext)
                engine.startSchedule()
                nudgeEngine = engine
            }
            .onDisappear {
                nudgeEngine?.stopSchedule()
                nudgeEngine = nil
            }
    }

    private func openNudgeFromNotification(id: UUID) {
        guard let nudge = nudge(withID: id),
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
            selectedItem = item
            openedItem = item
        case .staleInbox:
            openedItem = nil
            selectedItem = nil
            selection = .library
        case .dialecticalCheckIn:
            startCheckInConversation(from: nudge)
        case .connectionPrompt, .streak:
            break
        }
    }

    private func dismissNudgeFromNotification(id: UUID) {
        guard let nudge = nudge(withID: id),
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

    private func nudge(withID id: UUID) -> Nudge? {
        let allNudges = (try? modelContext.fetch(FetchDescriptor<Nudge>())) ?? []
        return allNudges.first(where: { $0.id == id })
    }

    private func startConversation(
        withPrompt prompt: String,
        seedItemIDs: [UUID] = [],
        injectionMode: ConversationPromptInjectionMode = .asUserMessage
    ) {
        var seedItems: [Item] = []
        if !seedItemIDs.isEmpty {
            let all = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
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

        selectedConversation = conversation
        withAnimation { showChatPanel = true }
    }

    private func startDiscussion(item: Item) {
        let service = DialecticsService()
        withAnimation { showChatPanel = true }
        Task { @MainActor in
            let conversation = await service.startDiscussion(item: item, context: modelContext)
            selectedConversation = conversation
        }
    }

    private func startCheckInConversation(from nudge: Nudge) {
        let trigger = nudge.checkInTrigger ?? .userInitiated
        let openingPrompt = nudge.checkInOpeningPrompt ?? ""
        let seedIDs = nudge.relatedItemIDs ?? []

        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
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

        selectedConversation = conversation
        withAnimation { showChatPanel = true }
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
        selectedConversation = conversation
        withAnimation { showChatPanel = true }
    }
}
