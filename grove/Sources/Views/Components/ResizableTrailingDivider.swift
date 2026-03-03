#if os(macOS)
import AppKit
#endif
import SwiftUI

enum TrailingPaneResizeMath {
    static let defaultCollapseOvershoot: CGFloat = 72

    static func nextWidth(
        initialWidth: CGFloat,
        dragTranslationX: CGFloat,
        minWidth: CGFloat,
        maxWidth: CGFloat
    ) -> CGFloat {
        let clampedMaxWidth = max(minWidth, maxWidth)
        let proposedWidth = initialWidth - dragTranslationX
        return min(max(proposedWidth, minWidth), clampedMaxWidth)
    }

    static func shouldCollapse(
        initialWidth: CGFloat,
        dragTranslationX: CGFloat,
        predictedEndTranslationX: CGFloat,
        minWidth: CGFloat,
        collapseOvershoot: CGFloat
    ) -> Bool {
        let collapseLimit = minWidth - collapseOvershoot
        let proposedWidth = initialWidth - dragTranslationX
        let predictedWidth = initialWidth - predictedEndTranslationX
        return proposedWidth < collapseLimit || predictedWidth < collapseLimit
    }
}

struct ResizableTrailingDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    var collapseOvershoot: CGFloat = TrailingPaneResizeMath.defaultCollapseOvershoot
    var onCollapse: (() -> Void)? = nil
    var onCommit: ((CGFloat) -> Void)? = nil

    @State private var dragInitialWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.borderPrimary)
            .frame(width: 1)
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    #if os(macOS)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    #endif
                    .gesture(dragGesture)
            }
            .accessibilityHidden(true)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let initialWidth = dragInitialWidth ?? width
                dragInitialWidth = initialWidth
                width = TrailingPaneResizeMath.nextWidth(
                    initialWidth: initialWidth,
                    dragTranslationX: value.translation.width,
                    minWidth: minWidth,
                    maxWidth: maxWidth
                )
            }
            .onEnded { value in
                let initialWidth = dragInitialWidth ?? width
                dragInitialWidth = nil

                if let onCollapse,
                   TrailingPaneResizeMath.shouldCollapse(
                        initialWidth: initialWidth,
                        dragTranslationX: value.translation.width,
                        predictedEndTranslationX: value.predictedEndTranslation.width,
                        minWidth: minWidth,
                        collapseOvershoot: collapseOvershoot
                   ) {
                    width = initialWidth
                    withAnimation(.easeOut(duration: 0.2)) {
                        onCollapse()
                    }
                    return
                }

                let committedWidth = width
                onCommit?(committedWidth)
            }
    }
}
