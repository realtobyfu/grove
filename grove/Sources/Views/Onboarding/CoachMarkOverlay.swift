import SwiftUI
import SwiftData

struct CoachMarkOverlay: View {
    var coachMarks: CoachMarkService
    @Query private var allItems: [Item]
    @Query(sort: \Board.sortOrder) private var boards: [Board]
    @Binding var showChatPanel: Bool

    private var itemCount: Int { allItems.count }
    private var boardCount: Int { boards.count }
    private var hasItemWithBoard: Bool { allItems.contains { !$0.boards.isEmpty } }

    var body: some View {
        if coachMarks.isActive, let step = coachMarks.currentStep {
            ZStack {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        coachMarks.dismissGuide()
                    }

                GeometryReader { geo in
                    stepCard(step: step, geo: geo)
                }
            }
            .onChange(of: itemCount) { oldCount, newCount in
                if coachMarks.currentStep == .saveLink, newCount > oldCount {
                    coachMarks.advanceStep()
                }
            }
            .onChange(of: boardCount) { oldCount, newCount in
                if coachMarks.currentStep == .createBoard, newCount > oldCount {
                    coachMarks.advanceStep()
                }
            }
            .onChange(of: hasItemWithBoard) {
                if coachMarks.currentStep == .assignToBoard, hasItemWithBoard {
                    coachMarks.advanceStep()
                }
            }
            .onChange(of: showChatPanel) {
                if coachMarks.currentStep == .tryDialectics, showChatPanel {
                    coachMarks.advanceStep()
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: step)
        }

        if coachMarks.showCompletionToast {
            VStack {
                Spacer()
                completionToast
                    .padding(.bottom, Spacing.xxl)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.easeInOut(duration: 0.3), value: coachMarks.showCompletionToast)
        }
    }

    // MARK: - Step Cards

    @ViewBuilder
    private func stepCard(step: CoachMarkStep, geo: GeometryProxy) -> some View {
        let size = geo.size
        switch step {
        case .saveLink:
            saveLinkCard
                .position(x: size.width * 0.5, y: 120)

        case .createBoard:
            createBoardCard
                .position(x: 240, y: size.height * 0.35)

        case .assignToBoard:
            assignToBoardCard
                .position(x: size.width * 0.4, y: 160)

        case .tryDialectics:
            tryDialecticsCard
                .position(x: size.width - 200, y: 80)
        }
    }

    private var saveLinkCard: some View {
        CoachMarkCard(
            title: "Save your first link",
            description: "Paste a URL to capture it.",
            actionLabel: "Save It",
            arrowEdge: .top,
            onAction: {
                NotificationCenter.default.post(
                    name: .groveCoachMarkPrefill,
                    object: "https://steve-yegge.medium.com/welcome-to-gas-town-4f25ee16dd04"
                )
            },
            onSkip: { coachMarks.skipStep() }
        )
    }

    private var createBoardCard: some View {
        CoachMarkCard(
            title: "Create a board",
            description: "Boards organize your items by topic.",
            actionLabel: "New Board",
            arrowEdge: .leading,
            onAction: {
                NotificationCenter.default.post(name: .groveNewBoard, object: nil)
            },
            onSkip: { coachMarks.skipStep() }
        )
    }

    private var assignToBoardCard: some View {
        CoachMarkCard(
            title: "Organize your item",
            description: "Add your saved link to the board.",
            actionLabel: "Got It",
            arrowEdge: .top,
            onAction: { coachMarks.advanceStep() },
            onSkip: { coachMarks.skipStep() }
        )
    }

    private var tryDialecticsCard: some View {
        CoachMarkCard(
            title: "Start a conversation",
            description: "Chat with Grove about your items.",
            actionLabel: "Open Chat",
            arrowEdge: .top,
            onAction: {
                withAnimation { showChatPanel = true }
            },
            onSkip: { coachMarks.skipStep() }
        )
    }

    // MARK: - Completion Toast

    private var completionToast: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
            Text("You're all set!")
                .font(.groveBodyMedium)
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.borderPrimary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
    }
}
