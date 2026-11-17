import Foundation
import Observation

/// A board the chat assistant wants to create. Nothing is written until the
/// user confirms it in the conversation.
struct BoardProposal: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let boardName: String
    let itemIDs: [UUID]
    let itemTitles: [String]
    let unmatchedTitles: [String]
    let conversationID: UUID
    /// The assistant reply that proposed it, so the card sits under that
    /// reply rather than under whatever came later. Nil when the turn ended
    /// without a reply; the card then sits at the end of the conversation.
    var messageID: UUID?

    init(
        id: UUID = UUID(),
        boardName: String,
        itemIDs: [UUID],
        itemTitles: [String],
        unmatchedTitles: [String],
        conversationID: UUID,
        messageID: UUID? = nil
    ) {
        self.id = id
        self.boardName = boardName
        self.itemIDs = itemIDs
        self.itemTitles = itemTitles
        self.unmatchedTitles = unmatchedTitles
        self.conversationID = conversationID
        self.messageID = messageID
    }

    static func itemCountLabel(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}

/// Pending proposals, one per conversation, kept in UserDefaults so a card
/// the assistant's reply promises is still there after a relaunch. A new
/// proposal replaces the old one. Read on demand; nothing is cached.
@MainActor
@Observable
final class BoardProposalStore {
    static let shared = BoardProposalStore()

    @ObservationIgnored private let defaults: UserDefaults
    /// Bumped on every write so views reading a proposal re-render.
    private var revision = 0

    nonisolated static let keyPrefix = "grove.chat.pendingBoardProposal."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func proposal(for conversationID: UUID) -> BoardProposal? {
        _ = revision
        guard let data = defaults.data(forKey: Self.key(for: conversationID)) else { return nil }
        return try? JSONDecoder().decode(BoardProposal.self, from: data)
    }

    func set(_ proposal: BoardProposal) {
        guard let data = try? JSONEncoder().encode(proposal) else { return }
        defaults.set(data, forKey: Self.key(for: proposal.conversationID))
        revision += 1
    }

    /// Removes and returns the pending proposal, so a double tap acts once.
    func take(for conversationID: UUID) -> BoardProposal? {
        let proposal = proposal(for: conversationID)
        remove(for: conversationID)
        return proposal
    }

    /// Drops a conversation's proposal, e.g. when the conversation is deleted.
    func remove(for conversationID: UUID) {
        let key = Self.key(for: conversationID)
        guard defaults.object(forKey: key) != nil else { return }
        defaults.removeObject(forKey: key)
        revision += 1
    }

    private static func key(for conversationID: UUID) -> String {
        keyPrefix + conversationID.uuidString
    }
}
