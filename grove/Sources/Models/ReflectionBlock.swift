import Foundation
import SwiftData

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

@Model
final class ReflectionBlock {
    var id: UUID = UUID()
    var item: Item?
    var blockTypeRaw: String = ReflectionBlockType.keyInsight.rawValue
    @Transient var blockType: ReflectionBlockType {
        get { ReflectionBlockType(rawValue: blockTypeRaw) ?? .keyInsight }
        set { blockTypeRaw = newValue.rawValue }
    }
    var content: String = ""
    var highlight: String?
    var position: Int = 0
    var videoTimestamp: Int?
    var conversation: Conversation?
    var createdAt: Date = Date.now

    init(item: Item, blockType: ReflectionBlockType, content: String = "", highlight: String? = nil, position: Int = 0, videoTimestamp: Int? = nil) {
        self.id = UUID()
        self.item = item
        self.blockTypeRaw = blockType.rawValue
        self.content = content
        self.highlight = highlight
        self.position = position
        self.videoTimestamp = videoTimestamp
        self.createdAt = .now
    }
}
