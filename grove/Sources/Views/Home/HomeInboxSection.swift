import SwiftUI

/// Inbox triage section on the Home screen with collapsible header.
struct HomeInboxSection: View {
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    let inboxCount: Int
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSectionHeader(title: "INBOX", count: inboxCount, isCollapsed: $isCollapsed)
            if !isCollapsed {
                InboxTriageView(selectedItem: $selectedItem, openedItem: $openedItem, isEmbedded: true)
            }
        }
    }
}
