import SwiftUI
import SwiftData

// MARK: - HomeView

struct HomeView: View {
    private static let maxDiscussionCards = 1

    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.updatedAt, order: .reverse) private var allItems: [Item]

    @State private var starterService = ConversationStarterService.shared
    /// The moment the page was last drawn for, moved on once a minute: the
    /// masthead's date and "Earlier today" both roll over with it when the
    /// window is left open past midnight.
    @State private var now = Date.now

    private var discussionBubbles: [PromptBubble] {
        Array(starterService.bubbles.prefix(Self.maxDiscussionCards))
    }

    private var earlierEntries: [TodayDigest.EarlierEntry] {
        TodayDigest.earlierToday(from: allItems, now: now)
    }

    private var continueNotes: [Item] {
        TodayDigest.continueNotes(from: allItems)
    }

    var body: some View {
        GeometryReader { proxy in
            page(size: proxy.size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
        .navigationTitle("")
        .onAppear {
            releaseStaleSelection()
        }
        .task {
            await starterService.refresh(items: allItems)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = .now
            }
        }
    }

    // MARK: - Page

    /// Arrived and Yours side by side when the page has room for both, and
    /// one column — Yours after Arrived — when it does not. The page is
    /// whatever the sidebar and the window's right page leave, so opening
    /// the right page narrows it exactly as a small window does.
    ///
    /// One scroll view and one pair of subviews in both arrangements: only
    /// the layout between them changes, so nothing on the page (the inbox's
    /// focus, an open review sheet) is rebuilt when the width crosses over.
    private func page(size: CGSize) -> some View {
        let isWide = TodayLayout.usesTwoColumns(pageWidth: size.width)
        let arrivedWidth = TodayLayout.arrivedContentWidth(
            pageWidth: size.width,
            gutter: LayoutDimensions.contentPaddingH
        )
        let columns = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        let coverBeside = TodayLayout.coverSitsBeside(contentWidth: arrivedWidth)
        // The measures that differ between the arrangements, worked out here
        // rather than as optional ternaries inside the modifier chain.
        let arrivedBottom: CGFloat = isWide ? Spacing.xxxl : Spacing.xxl
        let yoursMeasure: CGFloat? = isWide ? nil : TodayLayout.arrivedMeasure
        let yoursGutter: CGFloat = isWide ? TodayLayout.yoursGutter : LayoutDimensions.contentPaddingH
        let yoursTop: CGFloat = isWide ? LayoutDimensions.contentPaddingTop : 0
        let yoursWidth: CGFloat? = isWide ? TodayLayout.yoursColumnWidth : nil
        let yoursMaxWidth: CGFloat? = isWide ? nil : .infinity

        return ScrollView {
            columns {
                arrivedColumn(coverBeside: coverBeside)
                    .frame(maxWidth: TodayLayout.arrivedMeasure, alignment: .leading)
                    .padding(.horizontal, LayoutDimensions.contentPaddingH)
                    .padding(.top, LayoutDimensions.contentPaddingTop)
                    .padding(.bottom, arrivedBottom)
                    .frame(maxWidth: .infinity, alignment: .leading)

                yoursColumn
                    .frame(maxWidth: yoursMeasure, alignment: .leading)
                    .padding(.horizontal, yoursGutter)
                    .padding(.top, yoursTop)
                    .padding(.bottom, Spacing.xxxl)
                    .frame(width: yoursWidth, alignment: .leading)
                    .frame(maxWidth: yoursMaxWidth, alignment: .leading)
            }
            // At least the height of the page, so the Yours column's wash
            // runs to the bottom of the window when there is little to show.
            .frame(minHeight: size.height, alignment: .topLeading)
            .background(alignment: .trailing) {
                if isWide {
                    yoursWash
                }
            }
        }
    }

    /// The ground the Yours column sits on: the right page's own paper, with
    /// a hairline where the two columns meet.
    private var yoursWash: some View {
        Color.bgInspector
            .frame(width: TodayLayout.yoursColumnWidth)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.borderPrimary)
                    .frame(width: 1)
            }
            .accessibilityHidden(true)
    }

    // MARK: - Arrived

    private func arrivedColumn(coverBeside: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Today \u{00B7} Arrived")
                .sectionHeaderStyle()

            Text(TodayDigest.mastheadTitle(for: now))
                .font(.groveTitle)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .padding(.top, Spacing.xs)
                .accessibilityAddTraits(.isHeader)

            // The inline bar insets its own field by `Spacing.lg` on each
            // side. Taking that back here sets the field on the column's
            // edges, in line with the masthead above and the inbox below.
            CaptureBarView()
                .padding(.horizontal, -Spacing.lg)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.sm)

            HomeInboxSection(
                selectedItem: $selectedItem,
                openedItem: $openedItem,
                coverBeside: coverBeside
            )

            HomeEarlierSection(
                entries: earlierEntries,
                onOpen: { openItem($0) }
            )
        }
    }

    // MARK: - Yours

    private var yoursColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Yours")
                .sectionHeaderStyle()
                .padding(.bottom, Spacing.lg)

            HomeContinueSection(
                notes: continueNotes,
                onOpen: { openItem($0) },
                onNewNote: { NotificationCenter.default.post(name: .groveNewNote, object: nil) }
            )
            .padding(.bottom, Spacing.xl)

            // Shown only while cards are due; its bottom inset belongs to the
            // row, so a hidden row leaves no gap.
            LearningInvitationView(
                showsOnlyWhenDue: true,
                rowInsets: EdgeInsets(top: 0, leading: 0, bottom: Spacing.xl, trailing: 0)
            )

            HomeDiscussionSection(
                discussionBubbles: discussionBubbles,
                onOpenChat: { startDialectic(with: $0) },
                onStartWriting: { startWriting(with: $0.prompt) },
                onDismissBubble: { starterService.dismiss($0, in: modelContext) }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Opening

    /// Opens an item the way every list in the window does — selected and
    /// opened together — so the reader's Info tab and Export describe what
    /// is on screen. A note opens as its page.
    private func openItem(_ item: Item) {
        selectedItem = item
        openedItem = item
    }

    /// Today arrives with nothing selected.
    ///
    /// Back from the reader, the window still has the item that was open
    /// selected, and a selection brings up Info — which would take the room
    /// the Yours column sits in, uninvited, after every item read. Clicking
    /// the inbox's focused item selects it again.
    private func releaseStaleSelection() {
        if selectedItem != nil {
            selectedItem = nil
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
                    .padding(.horizontal, Spacing.xsm)
                    .padding(.vertical, 2)
                    .background(Color.accentBadge)
                    .foregroundStyle(Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.tag))

                Spacer()
            }
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
