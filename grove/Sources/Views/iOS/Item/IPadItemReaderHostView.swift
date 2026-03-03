import SwiftUI

/// iPad detail host that uses the shared mac-style reader workflow:
/// overview + reflections first, then in-app article web view when the user opts in.
struct IPadItemReaderHostView: View {
    let item: Item
    @State private var isWebViewActive = false

    var body: some View {
        ItemReaderView(
            item: item,
            isWebViewActive: $isWebViewActive,
            alwaysShowReflectionPanel: true
        )
        .navigationTitle(item.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
