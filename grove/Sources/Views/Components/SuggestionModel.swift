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

// MARK: - Suggestion Types (shared across HomeView and BoardDetailView)

enum SuggestionType: String {
    case reflect = "REFLECT"
    case revisit = "REVISIT"
    case synthesize = "SYNTHESIZE"
    case continueCourse = "CONTINUE"
    case nudge = "NUDGE"

    var systemImage: String {
        switch self {
        case .reflect: "pencil.and.outline"
        case .revisit: "arrow.counterclockwise"
        case .synthesize: "sparkles"
        case .continueCourse: "play.circle"
        case .nudge: "lightbulb"
        }
    }
}

struct Suggestion: Identifiable {
    let id = UUID()
    let type: SuggestionType
    let title: String
    let reason: String
    let item: Item?
    let board: Board?
    let nudge: Nudge?

    init(type: SuggestionType, title: String, reason: String, item: Item? = nil, board: Board? = nil, nudge: Nudge? = nil) {
        self.type = type
        self.title = title
        self.reason = reason
        self.item = item
        self.board = board
        self.nudge = nudge
    }
}
