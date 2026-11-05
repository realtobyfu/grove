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

    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.updatedAt, order: .reverse) private var allItems: [Item]

    @State private var starterService = ConversationStarterService.shared
    @State private var isInboxCollapsed = false
    @State private var isDiscussionCollapsed = false

    /// Personal captures only — newsletter issues live in the Newsletters
    /// section and must not inflate the inbox badge.
    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox && !$0.isFeedSuggestion }.count
    }

    private var discussionBubbles: [PromptBubble] {
        Array(starterService.bubbles.prefix(Self.maxDiscussionCards))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CaptureBarView()
                    .padding(.bottom, Spacing.lg)

                LearningInvitationView(
                    showsOnlyWhenDue: true,
                    rowInsets: EdgeInsets(top: 0, leading: 0, bottom: Spacing.xl, trailing: 0)
                )

                HomeInboxSection(
                    selectedItem: $selectedItem,
                    openedItem: $openedItem,
                    inboxCount: inboxCount,
                    isCollapsed: $isInboxCollapsed
                )
                .padding(.bottom, Spacing.xl)

                HomeDiscussionSection(
                    discussionBubbles: discussionBubbles,
                    isCollapsed: $isDiscussionCollapsed,
                    onOpenChat: { startDialectic(with: $0) },
                    onStartWriting: { startWriting(with: $0.prompt) },
                    onDismissBubble: { starterService.dismiss($0, in: modelContext) }
                )
                .padding(.bottom, Spacing.xl)

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.top, LayoutDimensions.contentPaddingTop)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
        .navigationTitle("")
        .task {
            await starterService.refresh(items: allItems)
        }
    }

    // MARK: - Starter Actions

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
        guard let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NotificationCenter.default.post(name: .groveNewNote, object: nil)
            return
        }
        NotificationCenter.default.post(name: .groveNewNoteWithPrompt, object: prompt)
    }

    private func startDialectic(with bubble: PromptBubble) {
        let prompt = bubble.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            openConversation(with: "")
            return
        }
        openConversation(with: prompt, seedItemIDs: bubble.clusterItemIDs)
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
