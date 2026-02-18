import SwiftUI
import SwiftData

// MARK: - Suggestion Model

private enum SuggestionType: String {
    case reflect = "REFLECT"
    case revisit = "REVISIT"
    case synthesize = "SYNTHESIZE"
    case continueCourse = "CONTINUE"

    var systemImage: String {
        switch self {
        case .reflect: "pencil.and.outline"
        case .revisit: "arrow.counterclockwise"
        case .synthesize: "sparkles"
        case .continueCourse: "play.circle"
        }
    }
}

private struct Suggestion: Identifiable {
    let id = UUID()
    let type: SuggestionType
    let title: String
    let reason: String
    let item: Item?
    let board: Board?
}

struct HomeView: View {
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Query(sort: \Course.createdAt) private var courses: [Course]
    @Query(sort: \LearningPath.updatedAt, order: .reverse) private var learningPaths: [LearningPath]
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    @State private var isInboxCollapsed = false
    @State private var isSuggestionsCollapsed = false
    @State private var isPathsCollapsed = false
    @State private var isConversationsCollapsed = false
    @State private var openedLearningPath: LearningPath?

    private var inboxCount: Int {
        allItems.filter { $0.status == .inbox }.count
    }

    private var activeConversations: [Conversation] {
        conversations.filter { !$0.isArchived }
    }

    // MARK: - Suggestions

    private var suggestions: [Suggestion] {
        var result: [Suggestion] = []

        // 1. Reflect — Active items with content but 0 reflections, by depthScore desc
        let reflectCandidates = allItems
            .filter { $0.status == .active && $0.content != nil && !$0.content!.isEmpty && $0.reflections.isEmpty }
            .sorted { $0.depthScore > $1.depthScore }
        if let top = reflectCandidates.first {
            result.append(Suggestion(
                type: .reflect,
                title: top.title,
                reason: "Has content but no reflections yet",
                item: top,
                board: nil
            ))
        }

        // 2. Revisit — Items overdue for resurfacing
        let revisitCandidates = allItems
            .filter { $0.isResurfacingOverdue }
            .sorted { $0.depthScore > $1.depthScore }
        if let top = revisitCandidates.first {
            result.append(Suggestion(
                type: .revisit,
                title: top.title,
                reason: "Due for spaced review",
                item: top,
                board: nil
            ))
        }

        // 3. Synthesize — Boards with 4+ active reflected items but no synthesis note
        for board in boards {
            guard result.count < 4 else { break }
            let activeItems = board.items.filter { $0.status == .active }
            let reflectedItems = activeItems.filter { !$0.reflections.isEmpty }
            let hasSynthesis = activeItems.contains { $0.metadata["isAIGenerated"] == "true" || $0.metadata["digest"] == "true" }
            if reflectedItems.count >= 4 && !hasSynthesis {
                result.append(Suggestion(
                    type: .synthesize,
                    title: board.title,
                    reason: "\(reflectedItems.count) reflected items ready to synthesize",
                    item: nil,
                    board: board
                ))
                break // only one synthesize suggestion
            }
        }

        // 4. Continue Course — Next unfinished lecture
        for course in courses {
            guard result.count < 4 else { break }
            if let next = course.nextLecture {
                result.append(Suggestion(
                    type: .continueCourse,
                    title: next.title,
                    reason: "\(course.title) — \(course.completedCount)/\(course.totalCount) done",
                    item: next,
                    board: nil
                ))
                break // only one course suggestion
            }
        }

        return Array(result.prefix(4))
    }

    var body: some View {
        if let path = openedLearningPath {
            LearningPathDetailView(learningPath: path, openedItem: $openedItem)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            openedLearningPath = nil
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .help("Back to Home")
                    }
                }
        } else {
            dashboard
        }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                // Capture bar
                CaptureBarView()

                // Inbox Section
                inboxSection

                // Suggested for You
                if !suggestions.isEmpty {
                    suggestionsSection
                }

                // Learning Paths Section
                if !learningPaths.isEmpty {
                    learningPathsSection
                }

                // Conversations Section
                if !activeConversations.isEmpty {
                    conversationsSection
                }

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.top, LayoutDimensions.contentPaddingTop)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
        .navigationTitle("")
    }

    // MARK: - Inbox Section

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSectionHeader(
                title: "Inbox",
                count: inboxCount,
                isCollapsed: $isInboxCollapsed
            )

            if !isInboxCollapsed {
                InboxTriageView(
                    selectedItem: $selectedItem,
                    openedItem: $openedItem,
                    isEmbedded: true
                )
            }
        }
    }

    // MARK: - Suggestions Section

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(
                title: "Suggested for You",
                count: suggestions.count,
                isCollapsed: $isSuggestionsCollapsed
            )

            if !isSuggestionsCollapsed {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 400), spacing: Spacing.md)],
                    spacing: Spacing.md
                ) {
                    ForEach(suggestions) { suggestion in
                        suggestionCard(suggestion)
                    }
                }
            }
        }
    }

    private func suggestionCard(_ suggestion: Suggestion) -> some View {
        Button {
            if let item = suggestion.item {
                openedItem = item
            }
        } label: {
            HStack(spacing: 0) {
                // Left accent bar
                Rectangle()
                    .fill(Color.accentSelection)
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Type badge
                    Text(suggestion.type.rawValue)
                        .font(.groveBadge)
                        .tracking(0.8)
                        .foregroundStyle(Color.textSecondary)

                    // Title
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: suggestion.type.systemImage)
                            .font(.groveBodySecondary)
                            .foregroundStyle(Color.textSecondary)
                        Text(suggestion.title)
                            .font(.groveBody)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }

                    // Reason
                    Text(suggestion.reason)
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Learning Paths Section

    private var learningPathsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(
                title: "Learning Paths",
                count: learningPaths.count,
                isCollapsed: $isPathsCollapsed
            )

            if !isPathsCollapsed {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 400), spacing: Spacing.md)],
                    spacing: Spacing.md
                ) {
                    ForEach(learningPaths) { path in
                        learningPathCard(path)
                    }
                }
            }
        }
    }

    private func learningPathCard(_ path: LearningPath) -> some View {
        let completedCount = path.steps.filter { $0.progress == .reflected && !$0.isSynthesisStep }.count
        let totalSteps = path.steps.filter { !$0.isSynthesisStep }.count
        let progress: Double = totalSteps > 0 ? Double(completedCount) / Double(totalSteps) : 0

        return Button {
            openedLearningPath = path
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(path.title)
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: Spacing.md) {
                    Text("\(completedCount)/\(totalSteps) completed")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.barTrack)
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentSelection)
                                .frame(width: geo.size.width * progress, height: 4)
                        }
                    }
                    .frame(height: 4)
                    .frame(maxWidth: 120)
                }

                HStack(spacing: Spacing.md) {
                    if let board = path.board {
                        HStack(spacing: 4) {
                            Image(systemName: board.icon ?? "folder")
                                .font(.groveBadge)
                            Text(board.title)
                                .font(.groveMeta)
                        }
                        .foregroundStyle(Color.textTertiary)
                    }

                    Text(path.createdAt.formatted(.dateTime.month().day()))
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Conversations Section

    private var conversationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HomeSectionHeader(
                title: "Recent Conversations",
                count: activeConversations.count,
                isCollapsed: $isConversationsCollapsed
            )

            if !isConversationsCollapsed {
                ForEach(activeConversations.prefix(5)) { conversation in
                    conversationRow(conversation)
                }
            }
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            NotificationCenter.default.post(name: .groveOpenConversation, object: conversation)
        } label: {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.title)
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    if let lastMsg = conversation.lastMessage, lastMsg.role != .system {
                        Text(lastMsg.content)
                            .font(.groveBodySecondary)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(conversation.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)

                Image(systemName: "chevron.right")
                    .font(.groveBadge)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Header

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
