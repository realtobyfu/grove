import SwiftUI

/// The inbox on Today: one item at a time, with the rest waiting as one-line
/// rows underneath. `InboxTriageView` draws the section's own label, with
/// the inbox's count; the focused item's place ("1 of 3") is on its card.
struct HomeInboxSection: View {
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    /// The column is wide enough for the focused item's cover to sit beside
    /// its text rather than above it.
    var coverBeside = true

    var body: some View {
        InboxTriageView(
            selectedItem: $selectedItem,
            openedItem: $openedItem,
            isEmbedded: true,
            focusCoverBeside: coverBeside
        )
    }
}
