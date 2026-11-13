import Foundation
import SwiftUI

// MARK: - Prompt Bubble (shared between HomeView and ConversationStarterService)

struct PromptBubble: Identifiable {
    let id = UUID()
    let prompt: String
    let label: String
    /// Set for ORGANIZE-type bubbles — the tag that defines the unboarded cluster.
    let clusterTag: String?
    /// Seed items for this prompt (used to scope conversation context).
    let clusterItemIDs: [UUID]
    /// Boards associated with the prompt's source items.
    let boardIDs: [UUID]
    /// The generator's internal candidate id ("contradiction", "stale_0", …) —
    /// records which context signal produced this bubble.
    let contextID: String?

    /// What a card shows. `label` stays the stored vocabulary that
    /// `StarterLLMGenerator` validates and the disk cache round-trips.
    var displayLabel: String {
        let stored = label.uppercased()
        return stored == "RESOLVE" ? "These two disagree" : stored
    }

    init(
        prompt: String,
        label: String,
        clusterTag: String? = nil,
        clusterItemIDs: [UUID] = [],
        boardIDs: [UUID] = [],
        contextID: String? = nil
    ) {
        self.prompt = prompt
        self.label = label
        self.clusterTag = clusterTag
        self.clusterItemIDs = clusterItemIDs
        self.boardIDs = boardIDs
        self.contextID = contextID
    }
}
