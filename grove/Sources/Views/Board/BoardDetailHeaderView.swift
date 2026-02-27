#if os(macOS)
import AppKit
#endif
import SwiftUI

/// Extracted from BoardDetailView — toolbar cluster, empty state, and prompt mode panel.
@MainActor
struct BoardDetailHeaderView {
    let board: Board
    let effectiveItems: [Item]
    let boardDiscussionSuggestions: [PromptBubble]
    let sortOption: BoardSortOption

    @Binding var viewMode: BoardViewMode
    @Binding var sortOptionBinding: BoardSortOption
    @Binding var showItemPicker: Bool
    @Binding var isSuggestionsCollapsed: Bool
    @Binding var paywallPresentation: PaywallPresentation?

    let onSelectSuggestion: (PromptBubble) -> Void
    let onRefreshSuggestions: () -> Void

    @Environment(EntitlementService.self) private var entitlement
    @Environment(PaywallCoordinator.self) private var paywallCoordinator

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: board.isSmart ? "sparkles.rectangle.stack" : (board.icon ?? "square.grid.2x2"))
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text(board.title)
                .font(.groveItemTitle)
                .foregroundStyle(Color.textPrimary)
            if board.isSmart {
                Text("No items match the tag rules yet. Tag items to see them appear here automatically.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if !board.smartRuleTags.isEmpty {
                    HStack(spacing: 4) {
                        Text("Rules:")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                        Text(board.smartRuleTags.map(\.name).joined(separator: board.smartRuleLogic == .and ? " AND " : " OR "))
                            .font(.groveMeta)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } else {
                Text("No items yet. Add items to this board to get started.")
                    .font(.groveBody)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar Cluster

    var synthesisButton: some View {
        Button {
            guard entitlement.canUse(.synthesis) else {
                paywallPresentation = paywallCoordinator.present(
                    feature: .synthesis,
                    source: .synthesisAction
                )
                return
            }
            showItemPicker = true
        } label: {
            Label("Synthesize", systemImage: "sparkles")
        }
        .buttonStyle(.bordered)
        .help("Generate an AI synthesis note from items in this board")
        .disabled(effectiveItems.count < AppConstants.Activity.synthesisMinItems)
    }

    var sortPicker: some View {
        Menu {
            ForEach(BoardSortOption.allCases, id: \.self) { option in
                if option == .manual && board.isSmart { EmptyView() } else {
                    Button {
                        sortOptionBinding = option
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .buttonStyle(.bordered)
        .help("Sort items (\(sortOption.rawValue))")
    }

    var viewModeButton: some View {
        Button {
            viewMode = viewMode == .grid ? .list : .grid
        } label: {
            Label(viewMode == .grid ? "List" : "Grid", systemImage: viewMode.iconName)
        }
        .buttonStyle(.bordered)
        .help(viewMode == .grid ? "Switch to list view" : "Switch to grid view")
    }

    @ViewBuilder
    var toolbarCluster: some View {
        HStack(spacing: Spacing.sm) {
            sortPicker
            viewModeButton
            synthesisButton
            if board.isSmart && !board.smartRuleTags.isEmpty {
                Image(systemName: "gearshape.2")
                    .help("Smart board rules: \(board.smartRuleTags.map(\.name).joined(separator: board.smartRuleLogic == .and ? " AND " : " OR "))")
            }
        }
    }

    // MARK: - Suggestions Bar

    @ViewBuilder
    var suggestionsBar: some View {
        if !boardDiscussionSuggestions.isEmpty {
            BoardSuggestionsView(
                suggestions: boardDiscussionSuggestions,
                isSuggestionsCollapsed: $isSuggestionsCollapsed,
                onSelectSuggestion: onSelectSuggestion,
                onRefresh: onRefreshSuggestions
            )
        }
    }
}

// MARK: - Prompt Mode Panel

struct BoardPromptModePanel: View {
    let label: String
    let prompt: String
    let onClose: () -> Void
    let onDialectic: () -> Void
    let onWrite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Text("PROMPT ACTIONS")
                    .sectionHeaderStyle()

                Spacer()

                Button {
                    onClose()
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
                .accessibilityHint("Return to board without opening an action.")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(label.uppercased())
                    .font(.groveBadge)
                    .tracking(0.8)
                    .foregroundStyle(Color.textSecondary)

                Text(prompt)
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
                    onDialectic()
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
                    onWrite()
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
}
