import SwiftUI
import SwiftData

struct DialecticalChatPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Binding var selectedConversation: Conversation?
    @Binding var isVisible: Bool
    var currentBoard: Board?
    var onNavigateToItem: ((Item) -> Void)?

    @State private var dialecticsService = DialecticsService()
    @State private var inputText = ""
    @State private var showConversationList = false
    @State private var connectionMessage: ChatMessage?
    @State private var connectionSourceIdx = 0
    @State private var connectionTargetIdx = 1
    @State private var connectionType: ConnectionType = .related
    @State private var reflectionMessage: ChatMessage?
    @State private var reflectionConversation: Conversation?
    @State private var noteMessage: ChatMessage?
    @State private var conversationToDelete: Conversation?

    private var activeConversation: Conversation? {
        selectedConversation
    }

    private var activeConversations: [Conversation] {
        conversations.filter { !$0.isArchived }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if let conversation = activeConversation {
                chatView(for: conversation)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgInspector)
        .sheet(item: $connectionMessage) { message in
            connectionSheet(for: message)
        }
        .sheet(item: $reflectionMessage) { message in
            reflectionSheet(for: message)
        }
        .sheet(item: $noteMessage) { message in
            saveNoteSheet(for: message)
        }
        .alert(
            "Delete Conversation Permanently?",
            isPresented: Binding(
                get: { conversationToDelete != nil },
                set: { if !$0 { conversationToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                conversationToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let conversation = conversationToDelete {
                    deleteConversation(conversation)
                }
            }
        } message: {
            if let conversation = conversationToDelete {
                Text("\"\(conversation.displayTitle)\" and \(conversation.messages.count) message(s) will be permanently deleted. This cannot be undone.")
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: Spacing.sm) {
            Text("DIALECTICAL CHAT")
                .font(.groveSectionHeader)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            Spacer()

            if let conversation = activeConversation {
                Text(conversation.displayTitle)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)

                Button(role: .destructive) {
                    conversationToDelete = conversation
                } label: {
                    Image(systemName: "trash")
                        .font(.groveBody)
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
                .help("Delete conversation")
            }

            Button {
                showConversationList.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.groveBody)
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .help("All conversations")
            .popover(isPresented: $showConversationList) {
                conversationListPopover
            }

            Button {
                startNewConversation()
            } label: {
                Image(systemName: "plus")
                    .font(.groveBody)
                    .foregroundStyle(Color.textMuted)
            }
            .buttonStyle(.plain)
            .help("New conversation")

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
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Chat View

    private func chatView(for conversation: Conversation) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(conversation.visibleMessages) { message in
                            messageBubble(message, conversation: conversation)
                                .id(message.id)
                        }

                        if dialecticsService.isGenerating {
                            thinkingIndicator
                        }

                        if let error = dialecticsService.lastError {
                            errorBubble(error)
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

            Divider()
            inputArea(for: conversation)
        }
    }

    // MARK: - Message Bubble

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage, conversation: Conversation) -> some View {
        if message.role == .user {
            userBubble(message)
        } else if message.role == .assistant {
            assistantBubble(message, conversation: conversation)
        }
    }

    private func userBubble(_ message: ChatMessage) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.content)
                .font(.groveBody)
                .foregroundStyle(Color.textInverse)
                .padding(Spacing.md)
                .background(Color.accentSelection)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
        }
    }

    private func assistantBubble(_ message: ChatMessage, conversation: Conversation) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                MarkdownTextView(markdown: message.content) { title in
                    navigateToItemByTitle(title)
                }
                .textSelection(.enabled)

                // Action buttons
                assistantActions(message: message, conversation: conversation)
            }
            .padding(Spacing.md)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentSelection)
                    .frame(width: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }

            Spacer(minLength: 40)
        }
    }

    // MARK: - Assistant Actions

    private func assistantActions(message: ChatMessage, conversation: Conversation) -> some View {
        HStack(spacing: Spacing.sm) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.groveBadge)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textMuted)

            Button {
                noteMessage = message
            } label: {
                Label("Save as note", systemImage: "note.text.badge.plus")
                    .font(.groveBadge)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.textMuted)

            if !message.referencedItemIDs.isEmpty {
                Button {
                    reflectionConversation = conversation
                    reflectionMessage = message
                } label: {
                    Label("Save as Reflection", systemImage: "text.badge.plus")
                        .font(.groveBadge)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textMuted)
            }

            if message.referencedItemIDs.count >= 2 {
                Button {
                    connectionMessage = message
                } label: {
                    Label("Create Connection", systemImage: "link.badge.plus")
                        .font(.groveBadge)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textMuted)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Wiki-Link Navigation

    private func navigateToItemByTitle(_ title: String) {
        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        if let item = allItems.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
            onNavigateToItem?(item)
        }
    }

    // MARK: - Thinking Indicator

    private var thinkingIndicator: some View {
        HStack {
            HStack(spacing: 4) {
                Text("Thinking")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
                ProgressView()
                    .controlSize(.mini)
            }
            .padding(Spacing.sm)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
        }
    }

    // MARK: - Error Bubble

    private func errorBubble(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.groveBody)
                .foregroundStyle(Color.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text("Unable to respond")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textSecondary)
                Text(message)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
    }

    // MARK: - Input Area

    private func inputArea(for conversation: Conversation) -> some View {
        VStack(spacing: Spacing.sm) {
            // Seed item pills
            if !conversation.seedItemIDs.isEmpty {
                seedItemPills(for: conversation)
            }

            HStack(alignment: .bottom, spacing: Spacing.sm) {
                TextField("Ask, challenge, or reflect...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.groveBody)
                    .lineLimit(1...5)
                    .padding(Spacing.sm)
                    .background(Color.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.borderInput, lineWidth: 1)
                    )
                    .onSubmit {
                        sendMessage(to: conversation)
                    }

                Button {
                    sendMessage(to: conversation)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.textMuted : Color.textPrimary)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || dialecticsService.isGenerating)
            }
        }
        .padding(Spacing.md)
    }

    private func seedItemPills(for conversation: Conversation) -> some View {
        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        let seeds = conversation.seedItemIDs.compactMap { id in
            allItems.first(where: { $0.id == id })
        }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                Text("Context:")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textMuted)
                ForEach(seeds, id: \.id) { item in
                    Button {
                        onNavigateToItem?(item)
                    } label: {
                        Text(item.title)
                            .font(.groveBadge)
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentBadge)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(Color.textTertiary)
            Text("Dialectical Chat")
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)
            Text("Start a conversation to explore your ideas through dialectical reasoning.")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Button {
                startNewConversation()
            } label: {
                Label("New Conversation", systemImage: "plus")
                    .font(.groveBodyMedium)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            if !activeConversations.isEmpty {
                Divider().padding(.horizontal, Spacing.xxl)
                Text("Recent")
                    .sectionHeaderStyle()
                ForEach(activeConversations.prefix(3)) { conv in
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

            Spacer()
        }
    }

    // MARK: - Conversation List Popover

    private var conversationListPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CONVERSATIONS")
                .sectionHeaderStyle()
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

            Divider()

            if activeConversations.isEmpty {
                Text("No conversations yet.")
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(Spacing.md)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(activeConversations) { conv in
                            HStack(spacing: Spacing.xs) {
                                Button {
                                    selectedConversation = conv
                                    showConversationList = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(conv.displayTitle)
                                                .font(.groveBody)
                                                .foregroundStyle(Color.textPrimary)
                                                .lineLimit(1)
                                            HStack(spacing: 4) {
                                                Text(conv.trigger.rawValue)
                                                    .font(.groveBadge)
                                                    .foregroundStyle(Color.textTertiary)
                                                Text(conv.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.groveMeta)
                                                    .foregroundStyle(Color.textTertiary)
                                            }
                                        }
                                        Spacer()
                                        Text("\(conv.visibleMessages.count) msgs")
                                            .font(.groveBadge)
                                            .foregroundStyle(Color.textMuted)
                                    }
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, Spacing.sm)
                                    .contentShape(Rectangle())
                                    .selectedItemStyle(selectedConversation?.id == conv.id)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    conversationToDelete = conv
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.groveBodySmall)
                                        .foregroundStyle(Color.textMuted)
                                }
                                .buttonStyle(.plain)
                                .help("Delete conversation")
                                .padding(.trailing, Spacing.sm)
                            }
                            Divider().padding(.leading, Spacing.md)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 300)
    }

    // MARK: - Actions

    private func startNewConversation() {
        let seedItems: [Item]
        if let board = currentBoard {
            // Seed with up to 10 active items from the current board, sorted by depth score
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
        selectedConversation = conversation
    }

    private func sendMessage(to conversation: Conversation) {
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

    private func deleteConversation(_ conversation: Conversation) {
        let nextConversation = activeConversations.first { $0.id != conversation.id }
        if selectedConversation?.id == conversation.id {
            selectedConversation = nextConversation
        }
        modelContext.delete(conversation)
        try? modelContext.save()
        conversationToDelete = nil
    }

    // MARK: - Save Note Sheet

    private func saveNoteSheet(for message: ChatMessage) -> some View {
        SaveNoteSheet(
            message: message,
            conversation: activeConversation,
            dialecticsService: dialecticsService,
            onDismiss: { noteMessage = nil }
        )
    }

    // MARK: - Reflection Sheet

    private func reflectionSheet(for message: ChatMessage) -> some View {
        SaveReflectionSheet(
            message: message,
            conversation: reflectionConversation,
            dialecticsService: dialecticsService,
            onDismiss: { reflectionMessage = nil }
        )
    }

    // MARK: - Connection Sheet

    private func connectionSheet(for message: ChatMessage) -> some View {
        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        let referenced = message.referencedItemIDs.compactMap { id in
            allItems.first(where: { $0.id == id })
        }

        return VStack(spacing: Spacing.lg) {
            Text("Create Connection")
                .font(.groveItemTitle)

            if referenced.count >= 2 {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("From:")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textMuted)
                    Text(referenced[0].title)
                        .font(.groveBody)

                    Text("To:")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textMuted)
                    Text(referenced.count > 1 ? referenced[1].title : "")
                        .font(.groveBody)

                    Picker("Type", selection: $connectionType) {
                        ForEach(ConnectionType.allCases, id: \.self) { type in
                            Text(type.displayLabel).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Button("Cancel") {
                        connectionMessage = nil
                    }
                    .buttonStyle(.bordered)

                    Button("Create") {
                        _ = dialecticsService.createConnection(
                            sourceTitle: referenced[0].title,
                            targetTitle: referenced[1].title,
                            type: connectionType,
                            context: modelContext
                        )
                        connectionMessage = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Need at least 2 referenced items to create a connection.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)

                Button("Close") {
                    connectionMessage = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 350)
    }
}

// MARK: - Save Reflection Sheet

private struct SaveReflectionSheet: View {
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
        let allItems = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        return message.referencedItemIDs.compactMap { id in
            allItems.first(where: { $0.id == id })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Save as Reflection")
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)

            // Target item picker
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

            // Block type picker
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

            // Content editor
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

            // Actions
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
        .padding(Spacing.xl)
        .frame(width: 420)
        .onAppear {
            editedContent = message.content
            selectedItemID = message.referencedItemIDs.first
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
        // Dismiss after a brief moment so the user sees the confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onDismiss()
        }
    }
}

// MARK: - Save Note Sheet

private struct SaveNoteSheet: View {
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

            // Title field
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

            // Content preview
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

            // Actions
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
        .padding(Spacing.xl)
        .frame(width: 420)
        .onAppear {
            editedTitle = extractTitle(from: message.content)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onDismiss()
        }
    }

    private func extractTitle(from content: String) -> String {
        // Take first sentence, capped at 100 characters
        let sentence = content.components(separatedBy: CharacterSet(charactersIn: ".?!")).first ?? ""
        let trimmed = sentence.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Note from conversation" }
        return trimmed.count > 100 ? String(trimmed.prefix(100)) : trimmed
    }
}
