import SwiftUI

/// Compact rendering of a captured highlight: left rule, optional mono-caps
/// kicker, two collapsed lines with a click-to-expand affordance, and a
/// separate arrow that jumps to the passage in the source. Expand and jump are
/// deliberately different targets so they never collide.
struct HighlightQuoteChip: View {
    let quote: String
    /// Mono-caps label above the quote (e.g. "FROM ARTICLE"). Hidden when nil.
    var kicker: String?
    /// Provided when the item has a source that can be scrolled to.
    var onJump: (() -> Void)?

    private let collapsedLineLimit = 2

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool {
        fullHeight - collapsedHeight > 1
    }

    /// Touch targets stay finger-sized on iOS, tight on the pointer platform.
    private var affordanceSide: CGFloat {
        #if os(iOS)
        return 44
        #else
        return 18
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(isHovered ? Color.textTertiary : Color.borderPrimary)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 3) {
                if let kicker {
                    Text(kicker.uppercased())
                        .font(.groveBadge)
                        .tracking(0.6)
                        .foregroundStyle(Color.textMuted)
                }

                quoteText
            }
            .padding(.leading, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingAffordances
        }
        .animation(.easeOut(duration: 0.15), value: isExpanded)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }

    // MARK: - Quote

    private var quoteText: some View {
        Text(quote)
            .font(.groveGhostText)
            .foregroundStyle(isHovered ? Color.textSecondary : Color.textTertiary)
            .lineLimit(isExpanded ? nil : collapsedLineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(measurementProbe)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isTruncated || isExpanded else { return }
                isExpanded.toggle()
            }
            .accessibilityLabel(quote)
            .accessibilityHint(isTruncated || isExpanded ? "Double tap to expand or collapse the quote" : "")
    }

    /// Two off-screen copies of the quote — clamped and unclamped — so the
    /// expand affordance only appears when the text actually overflows.
    private var measurementProbe: some View {
        ZStack {
            probeText(limit: collapsedLineLimit) { collapsedHeight = $0 }
            probeText(limit: nil) { fullHeight = $0 }
        }
        .hidden()
        .accessibilityHidden(true)
    }

    private func probeText(limit: Int?, onHeight: @escaping (CGFloat) -> Void) -> some View {
        Text(quote)
            .font(.groveGhostText)
            .lineLimit(limit)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { onHeight(proxy.size.height) }
                        .onChange(of: proxy.size.height) { _, height in onHeight(height) }
                }
            )
    }

    // MARK: - Affordances

    @ViewBuilder
    private var trailingAffordances: some View {
        HStack(spacing: 2) {
            if isTruncated || isExpanded {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .frame(width: affordanceSide, height: affordanceSide)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isHovered ? Color.textSecondary : Color.textMuted)
                .help(isExpanded ? "Collapse quote" : "Expand quote")
                .accessibilityLabel(isExpanded ? "Collapse quote" : "Expand quote")
            }

            if let onJump {
                Button(action: onJump) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .medium))
                        .frame(width: affordanceSide, height: affordanceSide)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isHovered ? Color.textSecondary : Color.textMuted)
                .help("Show in source")
                .accessibilityLabel("Show highlight in source")
            }
        }
        .padding(.leading, Spacing.xsm)
    }
}
