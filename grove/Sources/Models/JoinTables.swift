import CryptoKit
import Foundation
import SQLiteData

/// Two foreign keys, so this stays out of a shared board. CloudKit sharing
/// can't carry many-to-many links.
@Table("itemTags")
struct ItemTag: Hashable, Identifiable, Sendable {
    let id: UUID
    var itemID: Item.ID
    var tagID: Tag.ID
}

@Table("boardSmartRuleTags")
struct BoardSmartRuleTag: Hashable, Identifiable, Sendable {
    let id: UUID
    var boardID: Board.ID
    var tagID: Tag.ID
}

/// Up to ~275 KB each, so kept out of `items`: every list reads that table,
/// and SQLiteData turns BLOB columns into CKAssets.
@Table("itemThumbnails")
struct ItemThumbnail: Hashable, Identifiable, Sendable {
    @Column(primaryKey: true)
    let itemID: Item.ID
    var imageData: Data
    var id: Item.ID { itemID }
}

/// Board links past an item's first, kept from the many-to-many SwiftData
/// model so the import loses nothing. Local only: not synced, nothing reads
/// it yet, and it has no foreign keys so it can never block a delete. Rows
/// are cleared by triggers when their item or board goes.
@Table("extraBoardLinks")
struct ExtraBoardLink: Hashable, Identifiable, Sendable {
    let id: UUID
    var itemID: UUID
    var boardID: UUID
}

// MARK: - Deterministic IDs

extension UUID {
    /// A UUID derived from `parts`, the same on every device. Join rows use it
    /// so that importing on two devices converges instead of duplicating.
    init(derivedFrom parts: String...) {
        var bytes = Array(SHA256.hash(data: Data(parts.joined(separator: "|").utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 layout: name-based
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        self.init(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    fileprivate var key: String { uuidString.lowercased() }
}

extension ItemTag {
    init(itemID: UUID, tagID: UUID) {
        self.init(id: UUID(derivedFrom: "itemTags", itemID.key, tagID.key), itemID: itemID, tagID: tagID)
    }
}

extension BoardSmartRuleTag {
    init(boardID: UUID, tagID: UUID) {
        self.init(id: UUID(derivedFrom: "boardSmartRuleTags", boardID.key, tagID.key), boardID: boardID, tagID: tagID)
    }
}

extension ExtraBoardLink {
    init(itemID: UUID, boardID: UUID) {
        self.init(id: UUID(derivedFrom: "extraBoardLinks", itemID.key, boardID.key), itemID: itemID, boardID: boardID)
    }
}
