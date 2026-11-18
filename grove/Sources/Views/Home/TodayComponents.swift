import SwiftUI

// The pieces the Today page is set from: its column measures, its section
// labels, its one-line rows, and the keycap on New note. Everything is
// drawn with the shared colour, type, spacing and radius tokens, so a theme
// restyles this page along with the rest.

// MARK: - Layout

/// Today's two columns and the widths at which they rearrange. The measures
/// live here, in one place, because DesignTokens has none for this page.
enum TodayLayout {
    /// The "Yours" column, gutters included.
    static let yoursColumnWidth: CGFloat = 340
    /// Space either side of the Yours column's content: 300pt of content.
    static let yoursGutter: CGFloat = Spacing.xl
    /// The narrowest "Arrived" gets with Yours beside it. Below this the page
    /// is one column, with Yours after Arrived.
    static let minArrivedWidth: CGFloat = 440
    /// The widest Arrived's content runs, so a large window does not stretch
    /// the item being triaged into a banner.
    static let arrivedMeasure: CGFloat = 760
    /// From this content width up, the item being triaged sets its cover
    /// beside its text. Narrower, the cover sits above.
    static let coverBesideMinWidth: CGFloat = 520
    /// The cover beside the text, and its height when it sits above.
    static let coverSize = CGSize(width: 120, height: 90)
    static let coverBannerHeight: CGFloat = 120

    /// Two columns when the page — the space left once the sidebar and the
    /// window's right page have taken theirs — has room for both.
    static func usesTwoColumns(pageWidth: CGFloat) -> Bool {
        pageWidth >= minArrivedWidth + yoursColumnWidth
    }

    /// The width Arrived's content is set at, for a page this wide.
    /// - Parameter gutter: the page's horizontal content padding.
    static func arrivedContentWidth(pageWidth: CGFloat, gutter: CGFloat) -> CGFloat {
        let column = usesTwoColumns(pageWidth: pageWidth) ? pageWidth - yoursColumnWidth : pageWidth
        return max(0, min(arrivedMeasure, column - 2 * gutter))
    }

    static func coverSitsBeside(contentWidth: CGFloat) -> Bool {
        contentWidth >= coverBesideMinWidth
    }
}

// MARK: - Section Header

/// A section label on Today: tracked mono capitals, with an optional count
/// in a badge beside it.
struct TodaySectionHeader: View {
    let title: String
    var badge: String? = nil

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .sectionHeaderStyle()

            if let badge {
                Text(badge)
                    .font(.groveBadge)
                    .padding(.horizontal, Spacing.xsm)
                    .padding(.vertical, 2)
                    .background(Color.accentBadge)
                    .foregroundStyle(Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.tag))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Row

/// One line in a Today list: a mono lead (a position or a time), a title, and
/// a mono note at the trailing edge. Rows are separated by a hairline.
struct TodayRow: View {
    let lead: String
    /// The widest lead in the list. Every row reserves its width, so titles
    /// start on one vertical line whatever each row's own lead is.
    let leadSlot: String
    let title: String
    var note: String? = nil
    var showsRule = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text(leadSlot)
                    .hidden()
                    .overlay(alignment: .leading) {
                        Text(lead)
                    }
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
                    .fixedSize()

                Text(title)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let note, !note.isEmpty {
                    Text(note)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            #if os(iOS)
            .frame(minHeight: LayoutDimensions.minTouchTarget)
            #endif
            .background(isHovering ? Color.bgCard : Color.clear)
            .overlay(alignment: .bottom) {
                if showsRule {
                    Rectangle()
                        .fill(Color.borderPrimary)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Keycap

/// A key, set small in mono inside a hairline box: the hint on a button that
/// a key does the same thing.
struct Keycap: View {
    let key: String

    var body: some View {
        Text(key)
            // Mono Medium at the section-header size: the 11pt cap of the mockup.
            .font(.groveSectionHeader)
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, Spacing.xs)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.tag)
                    .strokeBorder(Color.borderInput, lineWidth: 1)
            }
            // The button's own label names the action; the cap is a visual hint.
            .accessibilityHidden(true)
    }
}

/// A button label with its menu shortcut after it ("New note ⌘⇧N").
struct KeyHintLabel: View {
    let title: String
    let key: String

    var body: some View {
        HStack(spacing: Spacing.xsm) {
            Text(title)
            Keycap(key: key)
        }
    }
}
