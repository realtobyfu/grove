import SwiftUI

/// iPad detail host that uses the shared mac-style reader workflow:
/// overview + reflections first, then in-app article web view when the user opts in.
struct IPadItemReaderHostView: View {
    let item: Item
    /// Opens a connected item in the detail column.
    let onOpenItem: (Item) -> Void

    @State private var isWebViewActive = false
    @State private var showInfo = false
    /// A connection tapped in Info, held until the popover has gone: a linked
    /// note opens in a sheet, which can't present over a closing popover.
    @State private var pendingLinkedItem: Item?

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) { infoButton }
        }
    }

    /// The popover anchors to the button, as inspectors do on iPad.
    private var infoButton: some View {
        Button {
            showInfo = true
        } label: {
            Image(systemName: "info.circle")
                .fontWeight(.medium)
                .foregroundStyle(Color.textPrimary)
                .frame(minWidth: LayoutDimensions.minTouchTarget, minHeight: LayoutDimensions.minTouchTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Info")
        .popover(isPresented: $showInfo, arrowEdge: .top) {
            ItemInspectorPanel(item: item) { linkedItem in
                if linkedItem.id != item.id {
                    pendingLinkedItem = linkedItem
                }
                showInfo = false
            }
            .frame(width: 380, height: 620)
            .onDisappear {
                guard let linkedItem = pendingLinkedItem else { return }
                pendingLinkedItem = nil
                onOpenItem(linkedItem)
            }
        }
    }
}
