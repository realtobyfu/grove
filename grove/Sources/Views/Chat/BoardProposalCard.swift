import SwiftUI

/// Asks the user to confirm a board the chat assistant proposed. Shown at the
/// end of the message list on macOS, iPhone, and iPad.
struct BoardProposalCard: View {
    static let scrollID = "board-proposal-card"
    private static let maxPreviewTitles = 3

    let proposal: BoardProposal
    let onCreate: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Create board “\(proposal.boardName)”?")
                .font(.groveBody)
                .foregroundStyle(Color.textPrimary)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(BoardProposal.itemCountLabel(proposal.itemIDs.count))
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)

                ForEach(proposal.itemTitles.prefix(Self.maxPreviewTitles).indices, id: \.self) { index in
                    Text(proposal.itemTitles[index])
                        .font(.groveBodySmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                if !proposal.unmatchedTitles.isEmpty {
                    Text("Not found: \(proposal.unmatchedTitles.joined(separator: ", "))")
                        .font(.groveMeta)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) {
                    createButton
                    declineButton
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    createButton
                    declineButton
                }
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentSelection)
                .frame(width: 2)
        }
        .cardStyle(cornerRadius: 8)
        .accessibilityElement(children: .contain)
    }

    private var createButton: some View {
        Button(action: onCreate) {
            Text("Create Board")
                .frame(minHeight: buttonMinHeight)
        }
        .buttonStyle(GroveCompactButtonStyle(prominent: true))
    }

    private var declineButton: some View {
        Button(action: onDecline) {
            Text("Not Now")
                .frame(minHeight: buttonMinHeight)
        }
        .buttonStyle(GroveCompactButtonStyle())
    }

    private var buttonMinHeight: CGFloat {
        #if os(iOS)
        LayoutDimensions.minTouchTarget
        #else
        0
        #endif
    }
}
