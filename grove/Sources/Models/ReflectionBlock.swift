import Foundation
import SQLiteData

enum ReflectionBlockType: String, Codable, CaseIterable {
    case keyInsight
    case connection
    case disagreement

    var displayName: String {
        switch self {
        case .keyInsight: "Key Insight"
        case .connection: "Connection"
        case .disagreement: "Disagreement"
        }
    }

    var systemImage: String {
        switch self {
        case .keyInsight: "lightbulb"
        case .connection: "link"
        case .disagreement: "exclamationmark.triangle"
        }
    }

    /// Fallback initializer for migrating old data with removed types.
    /// Old types (question, summary, freeform) map to keyInsight.
    init(legacy rawValue: String) {
        self = ReflectionBlockType(rawValue: rawValue) ?? .keyInsight
    }
}

@Table("reflectionBlocks")
struct ReflectionBlock: Hashable, Identifiable, Sendable {
    let id: UUID
    var itemID: Item.ID?
    /// Raw on purpose: rows from before the type set shrank hold values
    /// with no matching case, which `blockType` reads as `.keyInsight`.
    var blockTypeRaw: String = ReflectionBlockType.keyInsight.rawValue
    var content: String = ""
    var highlight: String?
    var position: Int = 0
    var videoTimestamp: Int?
    /// A plain ID so that this table keeps a single foreign key and can
    /// travel with a shared board. A trigger clears it when the conversation
    /// is deleted.
    var conversationID: UUID?
    var createdAt: Date = .now
}

extension ReflectionBlock {
    init(
        itemID: Item.ID,
        blockType: ReflectionBlockType,
        content: String = "",
        highlight: String? = nil,
        position: Int = 0,
        videoTimestamp: Int? = nil
    ) {
        self.init(
            id: UUID(),
            itemID: itemID,
            blockTypeRaw: blockType.rawValue,
            content: content,
            highlight: highlight,
            position: position,
            videoTimestamp: videoTimestamp
        )
    }

    var blockType: ReflectionBlockType {
        get { ReflectionBlockType(rawValue: blockTypeRaw) ?? .keyInsight }
        set { blockTypeRaw = newValue.rawValue }
    }
}

