import SwiftUI

// MARK: - Rail Modes

/// What the single right-hand rail is showing right now.
///
/// Before this existed, every trailing panel (inspector, Dialectics chat,
/// reflections list, reflection editor) mounted and unmounted itself with its
/// own width, its own transition and its own animation curve. Two of them could
/// be on screen at once mid-transition, each animating a different width, and
/// the article column re-wrapped once per panel. The rail collapses all of that
/// into one container with an explicit mode; content swaps *inside* the rail.
enum RightRailMode: String, Hashable, CaseIterable, Sendable {
    /// No rail at all. The content area takes the full width and nothing —
    /// not even a placeholder — is rendered on the trailing edge.
    case hidden
    /// Item metadata, boards, connections, backlinks.
    case inspector
    /// Dialectics chat.
    case dialectics
    /// Reader: the reflections list.
    case reflections
    /// Reader: the reflection editor.
    case reflectionEditor
    /// Reader: a source-linked flashcard draft, beside the unchanged source.
    case flashcardEditor
}

// MARK: - Metrics

/// The layout constants the rail is built from. One place, so a panel can't
/// quietly pick its own width or its own curve again.
enum RightRailMetrics {
    /// The standard rail width. Item-level panels all use it, which is what
    /// makes swapping between them a pure crossfade with no reflow at all.
    static let standardWidth: CGFloat = 360
    /// The reader's rail is a writing surface, so it legitimately runs wider.
    static let readerWidth: CGFloat = 440
    /// Reader prose measure. The web reader caps its column in CSS (66/80ch);
    /// this is the SwiftUI equivalent for natively rendered content.
    static let proseMeasure: CGFloat = 720
    /// The rail never squeezes the content area below this. Deliberately a
    /// subtraction rather than a fraction of the host width: a fraction would
    /// make the rail's width track an animating container, which is exactly
    /// the coupled reflow the rail exists to remove.
    static let minContentWidth: CGFloat = 360

    /// The one curve every rail width change and every coordinated sidebar
    /// collapse uses. Focus mode drives both from a single `withAnimation`
    /// with this animation so there is never a second, offset reflow.
    static let widthChange: Animation = .easeOut(duration: 0.25)
    /// Mode swaps at equal width crossfade instead of moving. The outgoing
    /// panel stays mounted until the incoming one is in, so there is no blank
    /// frame between them.
    static let contentCrossfade: Animation = .easeOut(duration: 0.18)
}

// MARK: - Mode Geometry

extension RightRailMode {
    /// Reflections and the reflection editor deliberately share one stored
    /// width: equal widths are what make Reflect a crossfade rather than a
    /// resize, which is the whole point of the rail.
    var persistenceKey: LayoutSettings.PaneWidthKey? {
        switch self {
        case .hidden: nil
        case .inspector: .contentInspector
        case .dialectics: .contentChat
        case .reflections, .reflectionEditor, .flashcardEditor: .readerReflections
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .hidden: 0
        case .inspector, .dialectics: 300
        case .reflections, .reflectionEditor, .flashcardEditor: 280
        }
    }

    /// Hard cap per mode, additionally bounded so the content area keeps
    /// `minContentWidth`. On any comfortably sized window the cap doesn't bind,
    /// so the resolved width stays a constant across a transition even though
    /// `available` is measured from a container that may itself be animating.
    func maxWidth(available: CGFloat?) -> CGFloat {
        let hardCap: CGFloat = switch self {
        case .hidden: 0
        case .inspector: 520
        case .dialectics: 560
        case .reflections, .reflectionEditor, .flashcardEditor: 720
        }
        guard let available, available > 0 else { return hardCap }
        return max(minWidth, min(hardCap, available - RightRailMetrics.minContentWidth))
    }

    /// The width this mode uses before the user has ever dragged it. A plain
    /// constant — never a fraction of the host — so it can't drift mid-animation.
    var defaultWidth: CGFloat {
        switch self {
        case .hidden: 0
        case .inspector, .dialectics: RightRailMetrics.standardWidth
        case .reflections, .reflectionEditor, .flashcardEditor: RightRailMetrics.readerWidth
        }
    }

    /// Mode → width. Constant for a given mode and host size: it never depends
    /// on what the panel happens to contain, so a mode change is a single
    /// discrete width step rather than a content-driven reflow.
    func resolvedWidth(available: CGFloat?, stored: CGFloat? = nil) -> CGFloat {
        guard self != .hidden else { return 0 }
        let raw = stored
            ?? persistenceKey.flatMap { LayoutSettings.width(for: $0) }
            ?? defaultWidth
        return min(max(raw, minWidth), maxWidth(available: available))
    }
}

// MARK: - Container

/// The right-hand column. Owns its width, its resize handle, and the crossfade
/// between modes; the host only says which mode is active and supplies the
/// content for it.
///
/// Transition contract:
/// - **Mode change at equal width** → crossfade only. Both panels are mounted
///   through the swap (`ZStack` + `.id(mode)` + opacity transition), so the
///   old content never leaves before the new content arrives.
/// - **Mode change that alters width** (including to and from `.hidden`) → one
///   `RightRailMetrics.widthChange` on the rail's outer frame. The rail's
///   *content* jumps straight to its final width and is revealed by the
///   growing clip, so nothing inside the rail re-lays-out mid-animation
///   either.
/// - **Drag-resize** → never animated (the width changes without the mode
///   changing, and the animation is keyed on the mode).
struct RightRailContainer<Content: View>: View {
    /// The active mode. `.hidden` renders nothing and occupies no width.
    let mode: RightRailMode
    /// Host width, used to bound the rail on narrow layouts. Optional because
    /// not every host sits inside a `GeometryReader`.
    var availableWidth: CGFloat?
    /// Called when the user drags the divider past the collapse threshold.
    var onCollapse: (() -> Void)?
    @ViewBuilder var content: (RightRailMode) -> Content

    /// In-flight drag widths, per mode. Committed values live in `LayoutSettings`.
    @State private var draggedWidths: [RightRailMode: CGFloat] = [:]
    /// Lets a rail that mounts already-visible (the reader's) animate in from
    /// zero instead of popping, so it interpolates against whatever rail is
    /// animating out above it rather than stacking beside it.
    @State private var hasAppeared = false

    init(
        mode: RightRailMode,
        availableWidth: CGFloat? = nil,
        onCollapse: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (RightRailMode) -> Content
    ) {
        self.mode = mode
        self.availableWidth = availableWidth
        self.onCollapse = onCollapse
        self.content = content
    }

    /// The width the rail's content is laid out at. Deliberately not gated on
    /// `hasAppeared`: the panel is built at its final width and revealed by
    /// the clip, never squeezed through intermediate widths.
    private var contentWidth: CGFloat {
        mode.resolvedWidth(available: availableWidth, stored: draggedWidths[mode])
    }

    /// The width the rail actually occupies in the layout. This is the value
    /// that animates.
    private var railWidth: CGFloat {
        hasAppeared ? contentWidth : 0
    }

    private var widthBinding: Binding<CGFloat> {
        Binding(
            get: { contentWidth },
            set: { draggedWidths[mode] = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            if mode != .hidden {
                ResizableTrailingDivider(
                    width: widthBinding,
                    minWidth: mode.minWidth,
                    maxWidth: mode.maxWidth(available: availableWidth),
                    onCollapse: { onCollapse?() },
                    onCommit: { width in
                        if let key = mode.persistenceKey {
                            LayoutSettings.setWidth(width, for: key)
                        }
                    }
                )
            }

            ZStack(alignment: .topLeading) {
                content(mode)
                    .frame(width: max(contentWidth, 1), alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .id(mode)
                    .transition(.opacity)
            }
            // Content swap: crossfade, and only the crossfade. Sits inside the
            // width animation below so it wins for this subtree.
            .animation(RightRailMetrics.contentCrossfade, value: mode)
            .frame(width: railWidth, alignment: .topLeading)
            .clipped()
        }
        // Keyed on mode (+ first appearance) rather than on the width itself so
        // that dragging the divider stays instant.
        .animation(RightRailMetrics.widthChange, value: WidthToken(mode: mode, hasAppeared: hasAppeared))
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(RightRailMetrics.widthChange) { hasAppeared = true }
        }
    }

    private struct WidthToken: Equatable {
        let mode: RightRailMode
        let hasAppeared: Bool
    }
}

// MARK: - Reader Measure Column

/// Holds reading content at a fixed measure and lets flexible gutters absorb
/// everything else.
///
/// This is what makes the rail's width animation free of prose reflow: when the
/// rail grows or collapses, the content area's width interpolates, but the text
/// container keeps the same width the entire time and the two `Spacer`s take up
/// the difference. The prose only re-wraps if the content area itself drops
/// below the measure, which on a normal window it never does during a rail
/// transition.
struct ReaderMeasureColumn<Content: View>: View {
    var measure: CGFloat = RightRailMetrics.proseMeasure
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content
                .frame(maxWidth: measure)
            Spacer(minLength: 0)
        }
    }
}
