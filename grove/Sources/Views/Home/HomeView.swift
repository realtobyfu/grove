import SwiftUI
import SwiftData

// MARK: - Home Primary Button Style

struct HomePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.groveBodySmall)
            .foregroundStyle(Color.textInverse)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(isEnabled ? Color.textPrimary : Color.textSecondary)
            .clipShape(.rect(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - HomeView

struct HomeView: View {
    private static let maxDiscussionCards = 1

    private struct PromptModeSelection {
        let prompt: String
        let label: String
        let clusterTag: String?
        let clusterItemIDs: [UUID]

        init(bubble: PromptBubble) {
            self.prompt = bubble.prompt
            self.label = bubble.label
            self.clusterTag = bubble.clusterTag
            self.clusterItemIDs = bubble.clusterItemIDs
        }
    }

    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.updatedAt, order: .reverse) private var allItems: [Item]
    @Query(sort: \Nudge.createdAt, order: .reverse) private var allNudges: [Nudge]

    @State private var starterService = ConversationStarterService.shared
    @State private var isInboxCollapsed = false
    @State private var isDiscussionCollapsed = false
    @State private var promptModeSelection: PromptModeSelection? = nil
    @State private var promptModePanelWidth: CGFloat = LayoutSettings.width(for: .homePrompt) ?? 330

    /// Personal captures only — newsletter issues live in the Newsletters
    /// section and must not inflate the inbox badge.
    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox && !$0.isFeedSuggestion }.count
    }

    private var discussionBubbles: [PromptBubble] {
        Array(starterService.bubbles.prefix(Self.maxDiscussionCards))
    }

    /// The one active resurface nudge, surfaced as a Think Next card instead of
    /// a standalone notice bar. Stale-inbox nudges are not shown on Home — the
    /// Inbox section with its live count is already on screen.
    private var resurfaceNudge: Nudge? {
        allNudges.first {
            $0.type == .resurface && ($0.status == .pending || $0.status == .shown) && $0.targetItem != nil
        }
    }

    var body: some View {
        GeometryReader { geo in
            let minPanelWidth: CGFloat = 280
            let maxPanelWidth = max(minPanelWidth, min(560, geo.size.width * 0.55))
            let clampedPanelWidth = min(max(promptModePanelWidth, minPanelWidth), maxPanelWidth)
            let panelWidthBinding = Binding(
                get: { clampedPanelWidth },
                set: { promptModePanelWidth = $0 }
            )

            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        CaptureBarView()
                            .padding(.bottom, Spacing.lg)

                        LearningInvitationView()
                            .padding(.bottom, Spacing.xl)

                        HomeInboxSection(
                            selectedItem: $selectedItem,
                            openedItem: $openedItem,
                            inboxCount: inboxCount,
                            isCollapsed: $isInboxCollapsed
                        )
                        .padding(.bottom, Spacing.xl)

                        HomeDiscussionSection(
                            resurfaceNudge: resurfaceNudge,
                            discussionBubbles: discussionBubbles,
                            isCollapsed: $isDiscussionCollapsed,
                            onBubbleTap: { presentModePanel(for: $0) },
                            onOpenNudge: { openNudgeItem($0) },
                            onDismissNudge: { dismissNudge($0) },
                            onDismissBubble: { dismissBubble($0) }
                        )
                        .padding(.bottom, Spacing.xl)

                        Spacer(minLength: Spacing.xxxl)
                    }
                    .padding(.horizontal, LayoutDimensions.contentPaddingH)
                    .padding(.top, LayoutDimensions.contentPaddingTop)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let selection = promptModeSelection {
                    ResizableTrailingDivider(
                        width: panelWidthBinding,
                        minWidth: minPanelWidth,
                        maxWidth: maxPanelWidth,
                        onCollapse: { promptModeSelection = nil }
                    ) { width in
                        LayoutSettings.setWidth(width, for: .homePrompt)
                    }

                    promptModePanel(for: selection)
                        .frame(width: panelWidthBinding.wrappedValue)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
        .navigationTitle("")
        .task {
            await starterService.refresh(items: allItems)
        }
        .onChange(of: resurfaceNudge?.id, initial: true) {
            guard let nudge = resurfaceNudge else { return }
            if nudge.status == .pending {
                nudge.status = .shown
                try? modelContext.save()
            }
            NudgeNotificationService.shared.cancel(for: nudge.id)
        }
        .animation(.easeInOut(duration: 0.2), value: promptModeSelection != nil)
    }

    // MARK: - Resurface Nudge Actions

    private func openNudgeItem(_ nudge: Nudge) {
        guard let item = nudge.targetItem else { return }
        ResurfacingService(modelContext: modelContext).recordEngagement(for: item)
        withAnimation(.easeOut(duration: 0.15)) {
            nudge.status = .actedOn
            NudgeSettings.recordAction(type: nudge.type, actedOn: true)
            try? modelContext.save()
        }
        NudgeNotificationService.shared.cancel(for: nudge.id)
        selectedItem = item
        openedItem = item
    }

    private func dismissNudge(_ nudge: Nudge) {
        withAnimation(.easeOut(duration: 0.15)) {
            nudge.status = .dismissed
            NudgeSettings.recordAction(type: nudge.type, actedOn: false)
            try? modelContext.save()
        }
        NudgeNotificationService.shared.cancel(for: nudge.id)
    }

    // MARK: - Starter Dismissal

    private func dismissBubble(_ bubble: PromptBubble) {
        // Rejecting a tension-derived starter also retires the detected tension itself.
        if bubble.contextID == "contradiction", bubble.clusterItemIDs.count == 2 {
            removeAutoContradiction(between: bubble.clusterItemIDs[0], and: bubble.clusterItemIDs[1])
        }
        starterService.dismiss(bubble)
    }

    /// Deletes the auto-generated "contradicts" Connection behind a rejected
    /// starter and blacklists the pair so the next detection run skips it.
    private func removeAutoContradiction(between a: UUID, and b: UUID) {
        TensionDetectionService.blacklistPair(a, b)

        let connections: [Connection] = modelContext.fetchAll()
        let matches = connections.filter { connection in
            guard connection.type == .contradicts, connection.isAutoGenerated,
                  let sourceID = connection.sourceItem?.id,
                  let targetID = connection.targetItem?.id else { return false }
            return (sourceID == a && targetID == b) || (sourceID == b && targetID == a)
        }
        guard !matches.isEmpty else { return }

        for connection in matches {
            connection.sourceItem?.outgoingConnections.removeAll { $0.id == connection.id }
            connection.targetItem?.incomingConnections.removeAll { $0.id == connection.id }
            modelContext.delete(connection)
        }
        try? modelContext.save()
    }

    // MARK: - Prompt Mode Panel & Actions

    private func promptModePanel(for selection: PromptModeSelection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Text("PROMPT ACTIONS")
                    .sectionHeaderStyle()

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        promptModeSelection = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(8)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close prompt actions")
                .accessibilityHint("Return to Home sections without opening an action.")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(selection.label.uppercased())
                    .font(.groveBadge)
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)

                Text(selection.prompt)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
            .padding(.horizontal, Spacing.md)

            VStack(spacing: Spacing.sm) {
                Button {
                    startDialectic(with: selection)
                } label: {
                    Label("Open Dialectics", systemImage: "bubble.left.and.bubble.right")
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    startWriting(with: selection.prompt)
                } label: {
                    Label("Start Writing", systemImage: "square.and.pencil")
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.md)

            Spacer(minLength: 0)
        }
        .background(Color.bgInspector)
    }

    private func presentModePanel(for bubble: PromptBubble) {
        withAnimation(.easeInOut(duration: 0.2)) {
            promptModeSelection = PromptModeSelection(bubble: bubble)
        }
    }

    private func openConversation(with prompt: String, seedItemIDs: [UUID] = []) {
        NotificationCenter.default.postConversationPrompt(
            ConversationPromptPayload(
                prompt: prompt,
                seedItemIDs: seedItemIDs,
                // Starters are assistant-voiced questions the user answers, so the
                // prompt opens the conversation as the assistant, not the user.
                injectionMode: .asAssistantGreeting
            )
        )
    }

    private func startWriting(with prompt: String?) {
        defer { promptModeSelection = nil }
        guard let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NotificationCenter.default.post(name: .groveNewNote, object: nil)
            return
        }
        NotificationCenter.default.post(name: .groveNewNoteWithPrompt, object: prompt)
    }

    private func startDialectic(with selection: PromptModeSelection?) {
        defer { promptModeSelection = nil }
        guard let selection else {
            openConversation(with: "")
            return
        }
        let prompt = selection.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            openConversation(with: "")
            return
        }
        openConversation(with: prompt, seedItemIDs: selection.clusterItemIDs)
    }
}

// MARK: - Suggested Conversation Card

struct SuggestedConversationCard: View {
    let label: String
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var onDismiss: (() -> Void)? = nil
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.accentSelection)
                    .frame(width: 2)

                HStack(spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(label.uppercased())
                            .font(.groveBadge)
                            .tracking(0.8)
                            .foregroundStyle(Color.textSecondary)

                        if subtitle != nil {
                            HStack(spacing: Spacing.sm) {
                                if let icon {
                                    Image(systemName: icon)
                                        .font(.groveBodySecondary)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Text(title)
                                    .font(.groveBody)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        } else {
                            Text(title)
                                .font(.groveBody)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .multilineTextAlignment(.leading)
                        }

                        if let subtitle {
                            Text(subtitle)
                                .font(.groveBodySecondary)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    if let onDismiss {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.textMuted)
                                .padding(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss suggestion")
                    }

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isHovered ? Color.textSecondary : Color.textMuted)
                        .animation(.easeOut(duration: 0.15), value: isHovered)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(isHovered ? Color.bgCard.opacity(0.85) : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? Color.borderInput : Color.borderPrimary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Section Header Style

struct HomeSectionHeader: View {
    let title: String
    let count: Int
    @Binding var isCollapsed: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 12)

                Text(title)
                    .sectionHeaderStyle()

                Text("\(count)")
                    .font(.groveBadge)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentBadge)
                    .foregroundStyle(Color.textPrimary)
                    .clipShape(Capsule())

                Spacer()
            }
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
