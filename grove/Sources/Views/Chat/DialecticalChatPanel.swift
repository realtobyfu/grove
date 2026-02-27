import SwiftUI
import SwiftData

struct DialecticalChatPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Binding var selectedConversation: Conversation?
    @Binding var isVisible: Bool
    var currentBoard: Board?
    var onNavigateToItem: ((Item) -> Void)?

    @State private var viewModel: DialecticalChatViewModel?

    private var activeConversation: Conversation? {
        selectedConversation
    }

    // MARK: - Bindings

    private var connectionMessageBinding: Binding<ChatMessage?> {
        Binding(
            get: { viewModel?.connectionMessage },
            set: { viewModel?.connectionMessage = $0 }
        )
    }

    private var reflectionMessageBinding: Binding<ChatMessage?> {
        Binding(
            get: { viewModel?.reflectionMessage },
            set: { viewModel?.reflectionMessage = $0 }
        )
    }

    private var noteMessageBinding: Binding<ChatMessage?> {
        Binding(
            get: { viewModel?.noteMessage },
            set: { viewModel?.noteMessage = $0 }
        )
    }

    private var paywallBinding: Binding<PaywallPresentation?> {
        Binding(
            get: { viewModel?.paywallPresentation },
            set: { viewModel?.paywallPresentation = $0 }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.conversationToDelete != nil },
            set: { if !$0 { viewModel?.conversationToDelete = nil } }
        )
    }

    private var showConversationListBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.showConversationList ?? false },
            set: { viewModel?.showConversationList = $0 }
        )
    }

    // MARK: - Body

    var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bgInspector)
            .onAppear {
                if viewModel == nil {
                    viewModel = DialecticalChatViewModel(modelContext: modelContext)
                }
            }
            .sheet(item: connectionMessageBinding) { message in
                connectionSheetContent(for: message)
            }
            .sheet(item: reflectionMessageBinding) { message in
                reflectionSheetContent(for: message)
            }
            .sheet(item: noteMessageBinding) { message in
                noteSheetContent(for: message)
            }
            .sheet(item: paywallBinding) { presentation in
                ProPaywallView(presentation: presentation)
            }
            .onReceive(NotificationCenter.default.publisher(for: .groveDialecticsLimitReached)) { _ in
                viewModel?.paywallPresentation = paywallCoordinator.present(
                    feature: .dialectics,
                    source: .dialecticsLimit
                )
            }
            .alert("Delete Conversation Permanently?", isPresented: deleteAlertBinding) {
                deleteAlertButtons
            } message: {
                deleteAlertMessage
            }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if let conversation = activeConversation {
                chatView(for: conversation)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Sheet Contents

    @ViewBuilder
    private func connectionSheetContent(for message: ChatMessage) -> some View {
        if let vm = viewModel {
            ChatConnectionSheet(
                message: message,
                referencedItems: vm.referencedItems(for: message),
                connectionType: Binding(
                    get: { vm.connectionType },
                    set: { vm.connectionType = $0 }
                ),
                onCreateConnection: {
                    vm.createConnection(from: message, type: vm.connectionType)
                },
                onDismiss: { vm.connectionMessage = nil }
            )
        }
    }

    @ViewBuilder
    private func reflectionSheetContent(for message: ChatMessage) -> some View {
        if let vm = viewModel {
            SaveReflectionSheet(
                message: message,
                conversation: vm.reflectionConversation,
                dialecticsService: vm.dialecticsService,
                onDismiss: { vm.reflectionMessage = nil }
            )
        }
    }

    @ViewBuilder
    private func noteSheetContent(for message: ChatMessage) -> some View {
        if let vm = viewModel {
            SaveNoteSheet(
                message: message,
                conversation: activeConversation,
                dialecticsService: vm.dialecticsService,
                onDismiss: { vm.noteMessage = nil }
            )
        }
    }

    // MARK: - Alert

    @ViewBuilder
    private var deleteAlertButtons: some View {
        Button("Cancel", role: .cancel) {
            viewModel?.conversationToDelete = nil
        }
        Button("Delete", role: .destructive) {
            if let conversation = viewModel?.conversationToDelete {
                viewModel?.deleteConversation(
                    conversation,
                    selectedConversation: $selectedConversation,
                    conversations: conversations
                )
            }
        }
    }

    @ViewBuilder
    private var deleteAlertMessage: some View {
        if let conversation = viewModel?.conversationToDelete {
            let count = conversation.messages.count
            Text("\"\(conversation.displayTitle)\" and \(count) message(s) will be permanently deleted. This cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: Spacing.sm) {
            Text("DIALECTICS")
                .font(.groveSectionHeader)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            Spacer()

            if let conversation = activeConversation {
                headerConversationControls(conversation)
            }

            conversationListButton
            newConversationButton
            closeButton
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    @ViewBuilder
    private func headerConversationControls(_ conversation: Conversation) -> some View {
        Text(conversation.displayTitle)
            .font(.groveBodySmall)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)

        Button(role: .destructive) {
            viewModel?.conversationToDelete = conversation
        } label: {
            Image(systemName: "trash")
                .font(.groveBody)
                .foregroundStyle(Color.textMuted)
        }
        .buttonStyle(.plain)
        .help("Delete conversation")
        .accessibilityLabel("Delete conversation \(conversation.displayTitle)")
        .accessibilityHint("Permanently removes this conversation.")
    }

    private var conversationListButton: some View {
        Button {
            viewModel?.showConversationList.toggle()
        } label: {
            Image(systemName: "list.bullet")
                .font(.groveBody)
                .foregroundStyle(Color.textMuted)
        }
        .buttonStyle(.plain)
        .help("All conversations")
        .accessibilityLabel("Show all conversations")
        .accessibilityHint("Opens the conversation history popover.")
        .popover(isPresented: showConversationListBinding) {
            conversationListPopoverContent
        }
    }

    @ViewBuilder
    private var conversationListPopoverContent: some View {
        if let vm = viewModel {
            let filtered = vm.filteredConversations(from: conversations, entitlement: entitlement)
            let visible = vm.visibleHistoryConversations(from: conversations, entitlement: entitlement)
            ConversationListPopover(
                conversations: visible,
                filteredConversations: filtered,
                isHistoryCapped: vm.isHistoryCapped(conversations: conversations, entitlement: entitlement),
                trimmedQuery: vm.trimmedConversationListQuery,
                searchQuery: Binding(
                    get: { vm.conversationListQuery },
                    set: { vm.conversationListQuery = $0 }
                ),
                selectionID: Binding(
                    get: { vm.conversationListSelectionID },
                    set: { vm.conversationListSelectionID = $0 }
                ),
                entitlement: entitlement,
                onSelectConversation: { conv in
                    vm.openConversationFromList(conv, selectedConversation: $selectedConversation)
                },
                onDeleteConversation: { conv in
                    vm.conversationToDelete = conv
                },
                onUnlockPro: {
                    vm.paywallPresentation = paywallCoordinator.present(
                        feature: .fullHistory,
                        source: .chatHistory
                    )
                },
                onPrepare: {
                    vm.prepareConversationListPopover(selectedConversation: selectedConversation)
                },
                onSyncSelection: {
                    vm.syncConversationListSelection(
                        conversations: filtered,
                        selectedConversation: selectedConversation
                    )
                }
            )
        }
    }

    private var newConversationButton: some View {
        Button {
            viewModel?.startNewConversation(
                selectedConversation: $selectedConversation,
                currentBoard: currentBoard,
                entitlement: entitlement,
                paywallCoordinator: paywallCoordinator
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.groveBody)
                    .foregroundStyle(Color.textMuted)
                if !entitlement.isPro {
                    Text("\(entitlement.remaining(.dialectics))/\(MeteredFeature.dialectics.freeLimit)")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .help("New conversation")
        .accessibilityLabel("New conversation")
        .accessibilityHint("Starts a fresh Dialectics conversation.")
    }

    private var closeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isVisible = false
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .padding(6)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.borderPrimary, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Close chat")
        .accessibilityLabel("Close Dialectics")
        .accessibilityHint("Hides the Dialectics panel.")
    }

    // MARK: - Chat View

    private func chatView(for conversation: Conversation) -> some View {
        VStack(spacing: 0) {
            chatMessages(for: conversation)
            Divider()
            chatInput(for: conversation)
        }
    }

    private func chatMessages(for conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.md) {
                    if let vm = viewModel {
                        ForEach(conversation.visibleMessages) { message in
                            ChatMessageBubble(
                                message: message,
                                conversation: conversation,
                                dialecticsService: vm.dialecticsService,
                                onWikiLinkTapped: { title in
                                    vm.navigateToItemByTitle(title, onNavigateToItem: onNavigateToItem)
                                },
                                onConnectionRequest: { msg in
                                    vm.connectionMessage = msg
                                },
                                onReflectionRequest: { msg, conv in
                                    vm.reflectionConversation = conv
                                    vm.reflectionMessage = msg
                                },
                                onNoteRequest: { msg in
                                    vm.noteMessage = msg
                                }
                            )
                            .id(message.id)
                        }

                        if vm.dialecticsService.isGenerating {
                            ChatThinkingIndicator()
                        }

                        if let error = vm.dialecticsService.lastError {
                            ChatErrorBubble(message: error)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .onChange(of: conversation.messages.count) {
                if let lastID = conversation.visibleMessages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chatInput(for conversation: Conversation) -> some View {
        if let vm = viewModel {
            ChatInputArea(
                inputText: Binding(
                    get: { vm.inputText },
                    set: { vm.inputText = $0 }
                ),
                conversation: conversation,
                isGenerating: vm.dialecticsService.isGenerating,
                seeds: vm.seedItems(for: conversation),
                onSend: { vm.sendMessage(to: conversation) },
                onNavigateToItem: onNavigateToItem
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            emptyStateHeader
            emptyStateNewButton
            emptyStateRecent
            Spacer()
        }
    }

    private var emptyStateHeader: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("Dialectics")
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)
            Text("Start a conversation to explore your ideas through dialectical reasoning.")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
        }
    }

    private var emptyStateNewButton: some View {
        Button {
            viewModel?.startNewConversation(
                selectedConversation: $selectedConversation,
                currentBoard: currentBoard,
                entitlement: entitlement,
                paywallCoordinator: paywallCoordinator
            )
        } label: {
            Label("New Conversation", systemImage: "plus")
                .font(.groveBodyMedium)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    @ViewBuilder
    private var emptyStateRecent: some View {
        if let vm = viewModel {
            let active = vm.activeConversations(from: conversations)
            if !active.isEmpty {
                VStack(spacing: Spacing.lg) {
                    Divider().padding(.horizontal, Spacing.xxl)
                    Text("Recent")
                        .sectionHeaderStyle()
                    ForEach(active.prefix(3)) { conv in
                        recentConversationRow(conv)
                    }
                }
            }
        }
    }

    private func recentConversationRow(_ conv: Conversation) -> some View {
        Button {
            selectedConversation = conv
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conv.displayTitle)
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(conv.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.groveMeta)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Save Reflection Sheet

struct SaveReflectionSheet: View {
    let message: ChatMessage
    let conversation: Conversation?
    let dialecticsService: DialecticsService
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selectedItemID: UUID?
    @State private var selectedBlockType: ReflectionBlockType = .keyInsight
    @State private var editedContent: String = ""
    @State private var saved = false

    private var referencedItems: [Item] {
        let allItems: [Item] = modelContext.fetchAll()
        return message.referencedItemIDs.compactMap { id in
            allItems.first(where: { $0.id == id })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Save as Reflection")
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)

            itemPicker
            blockTypePicker
            contentEditor
            actionButtons
        }
        .padding(Spacing.xl)
        .frame(width: 420)
        .onAppear {
            editedContent = message.content
            selectedItemID = message.referencedItemIDs.first
        }
    }

    private var itemPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("SAVE TO ITEM")
                .sectionHeaderStyle()

            ForEach(referencedItems, id: \.id) { item in
                Button {
                    selectedItemID = item.id
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: selectedItemID == item.id ? "checkmark.circle.fill" : "circle")
                            .font(.groveBody)
                            .foregroundStyle(selectedItemID == item.id ? Color.textPrimary : Color.textMuted)
                        Image(systemName: item.type.iconName)
                            .font(.groveBadge)
                            .foregroundStyle(Color.textSecondary)
                        Text(item.title)
                            .font(.groveBody)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var blockTypePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("REFLECTION TYPE")
                .sectionHeaderStyle()

            HStack(spacing: Spacing.sm) {
                ForEach(ReflectionBlockType.allCases, id: \.self) { type in
                    Button {
                        selectedBlockType = type
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: type.systemImage)
                                .font(.groveBadge)
                            Text(type.displayName)
                                .font(.groveBadge)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selectedBlockType == type ? Color.accentBadge : Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedBlockType == type ? Color.textPrimary : Color.textSecondary)
                }
            }
        }
    }

    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("CONTENT")
                .sectionHeaderStyle()

            TextEditor(text: $editedContent)
                .font(.groveBody)
                .frame(minHeight: 100, maxHeight: 200)
                .padding(Spacing.xs)
                .background(Color.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.borderInput, lineWidth: 1)
                )
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Cancel") {
                onDismiss()
            }
            .buttonStyle(.bordered)

            Spacer()

            if saved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)
            }

            Button("Save Reflection") {
                saveReflection()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentSelection)
            .disabled(selectedItemID == nil || editedContent.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func saveReflection() {
        guard let itemID = selectedItemID,
              let item = referencedItems.first(where: { $0.id == itemID }),
              let conv = conversation else { return }

        _ = dialecticsService.saveAsReflection(
            content: editedContent,
            itemTitle: item.title,
            blockType: selectedBlockType,
            conversation: conv,
            context: modelContext
        )
        saved = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            onDismiss()
        }
    }
}

// MARK: - Save Note Sheet

struct SaveNoteSheet: View {
    let message: ChatMessage
    let conversation: Conversation?
    let dialecticsService: DialecticsService
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var editedTitle: String = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Save as Note")
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)

            titleField
            contentPreview
            noteActionButtons
        }
        .padding(Spacing.xl)
        .frame(width: 420)
        .onAppear {
            editedTitle = extractTitle(from: message.content)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("TITLE")
                .sectionHeaderStyle()

            TextField("Note title", text: $editedTitle)
                .textFieldStyle(.plain)
                .font(.groveBody)
                .padding(Spacing.xs)
                .background(Color.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.borderInput, lineWidth: 1)
                )
        }
    }

    private var contentPreview: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("CONTENT")
                .sectionHeaderStyle()

            ScrollView {
                Text(message.content)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            .padding(Spacing.xs)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.borderInput, lineWidth: 1)
            )
        }
    }

    private var noteActionButtons: some View {
        HStack {
            Button("Cancel") {
                onDismiss()
            }
            .buttonStyle(.bordered)

            Spacer()

            if saved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)
            }

            Button("Save Note") {
                saveNote()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentSelection)
            .disabled(editedTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func saveNote() {
        guard let conv = conversation else { return }
        _ = dialecticsService.saveAsNote(
            content: message.content,
            title: editedTitle,
            conversation: conv,
            context: modelContext
        )
        saved = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            onDismiss()
        }
    }

    private func extractTitle(from content: String) -> String {
        let sentence = content.components(separatedBy: CharacterSet(charactersIn: ".?!")).first ?? ""
        let trimmed = sentence.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Note from conversation" }
        return trimmed.count > 100 ? String(trimmed.prefix(100)) : trimmed
    }
}
