import Foundation
import SwiftData

enum ReflectionBlockType: String, Codable, CaseIterable {
    case keyInsight
    case connection
    case question
    case disagreement
    case summary
    case freeform

    var displayName: String {
        switch self {
        case .keyInsight: "Key Insight"
        case .connection: "Connection"
        case .question: "Question"
        case .disagreement: "Disagreement"
        case .summary: "Summary"
        case .freeform: "Freeform"
        }
    }

    var systemImage: String {
        switch self {
        case .keyInsight: "lightbulb"
        case .connection: "link"
        case .question: "questionmark.circle"
        case .disagreement: "exclamationmark.triangle"
        case .summary: "doc.plaintext"
        case .freeform: "text.alignleft"
        }
    }
}

@Model
final class ReflectionBlock {
    var id: UUID
    var item: Item?
    var blockType: ReflectionBlockType
    var content: String
    var highlight: String?
    var position: Int
    var videoTimestamp: Int?
    var createdAt: Date

    init(item: Item, blockType: ReflectionBlockType, content: String = "", highlight: String? = nil, position: Int = 0, videoTimestamp: Int? = nil) {
        self.id = UUID()
        self.item = item
        self.blockType = blockType
        self.content = content
        self.highlight = highlight
        self.position = position
        self.videoTimestamp = videoTimestamp
        self.createdAt = .now
    }
}
