import SQLiteData
import SwiftUI

/// Hands `content` an item's thumbnail. Thumbnails are large and live in their own
/// table, so each one is read where it is shown rather than with the item.
struct ItemThumbnailReader<Content: View>: View {
    @FetchOne private var thumbnail: ItemThumbnail?
    private let content: (Data?) -> Content

    init(itemID: Item.ID, @ViewBuilder content: @escaping (Data?) -> Content) {
        _thumbnail = FetchOne(wrappedValue: nil, ItemThumbnail.find(itemID))
        self.content = content
    }

    var body: some View {
        content(thumbnail?.imageData)
    }
}
