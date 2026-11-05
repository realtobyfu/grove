import Foundation
import Observation

/// A board the chat assistant wants to create. Nothing is written until the
/// user confirms it in the conversation.
struct BoardProposal: Identifiable, Equatable, Sendable {
    let id = UUID()
    let boardName: String
    let itemIDs: [UUID]
    let itemTitles: [String]
    let unmatchedTitles: [String]
    let conversationID: UUID

    static func itemCountLabel(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}

/// In-memory pending proposals, one per conversation. A new proposal replaces
/// the old one, and none survive a relaunch.
@MainActor
@Observable
final class BoardProposalStore {
    private var proposals: [UUID: BoardProposal] = [:]

    func proposal(for conversationID: UUID) -> BoardProposal? {
        proposals[conversationID]
    }

    func set(_ proposal: BoardProposal) {
        proposals[proposal.conversationID] = proposal
    }

    /// Removes and returns the pending proposal, so a double tap acts once.
    func take(for conversationID: UUID) -> BoardProposal? {
        proposals.removeValue(forKey: conversationID)
    }
}
