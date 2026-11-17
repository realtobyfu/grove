import CoreGraphics

/// How the reader's navigation strip sheds controls into its `…` menu as the
/// reading pane narrows. Narrow panes hand controls to the menu rather than
/// letting the labels crush each other into vertical stacks of single letters.
///
/// Pure layout policy, kept out of `ItemReaderWebViewPanel` so the width
/// ladder and what each rung seats can be tested at their edges.
enum ReaderStripLayout {
    /// How much of the strip the reading pane can actually seat.
    enum Tier: Equatable, Sendable {
        /// Everything on the strip.
        case full
        /// Reflect, Open in Browser and Full Screen move into the menu.
        case compact
        /// Text size, zoom and Reader|Original move into the menu too, and
        /// Overview keeps only its chevron. What is left is the way out,
        /// where you are, and `…`.
        case minimal
    }

    /// The controls whose place depends on the tier. Everything else — the
    /// Overview chevron, the page-history chevrons, the domain and `…`
    /// itself — stays on the strip at every width.
    enum Control: CaseIterable, Sendable {
        /// The word "Overview" beside the back chevron.
        case overviewLabel
        /// Text size in Reader, page zoom on the live page.
        case sizeControls
        /// Enter / Exit Full Screen (macOS only).
        case fullScreen
        /// READER | ORIGINAL, shown only when the page has, or may yet have,
        /// a reader view.
        case readerMode
        case reflect
        case openInBrowser
    }

    /// Below this width the strip folds to `.compact`.
    static let compactBelowWidth: CGFloat = 620
    /// Below this width the strip folds to `.minimal`.
    static let minimalBelowWidth: CGFloat = 480

    /// The tier for a measured strip width.
    ///
    /// The strip is measured before the tier can be known, so an unmeasured
    /// (zero) width renders `.full` and settles within a frame. Thresholds
    /// are the widths at which the next cluster stops fitting alongside a
    /// truncated domain.
    ///
    /// Text size and zoom sit near the top of the ladder rather than in the
    /// middle of it: they are what gets adjusted *while* reading, so Reflect,
    /// Open in Browser, Full Screen and finally Reader│Original all give way
    /// before they do.
    static func tier(forWidth width: CGFloat) -> Tier {
        guard width > 0 else { return .full }
        if width < minimalBelowWidth { return .minimal }
        if width < compactBelowWidth { return .compact }
        return .full
    }

    /// Whether `control` keeps its own slot on the strip at `tier`.
    static func isOnStrip(_ control: Control, in tier: Tier) -> Bool {
        switch control {
        case .overviewLabel, .sizeControls, .readerMode:
            tier != .minimal
        case .fullScreen, .reflect, .openInBrowser:
            tier == .full
        }
    }

    /// Whether `control` gets a stand-in entry in the `…` menu at `tier`
    /// because the strip could not seat it.
    ///
    /// The Overview label has no stand-in — at the narrowest the chevron
    /// carries the meaning alone — and the size controls need none: the menu
    /// always carries the full text-size or zoom section whatever the width.
    static func isFoldedIntoMenu(_ control: Control, in tier: Tier) -> Bool {
        switch control {
        case .overviewLabel, .sizeControls:
            false
        case .fullScreen, .readerMode, .reflect, .openInBrowser:
            !isOnStrip(control, in: tier)
        }
    }
}
