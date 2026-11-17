#if os(macOS)
import AppKit
#endif
import SwiftUI
import SwiftData

/// A board as a trail: one column at the reading measure, in the user's own
/// order. Sources are numbered one-line rows; the user's notes are set in
/// place between them as text.
///
/// The split into numbered sources and inline notes lives in `BoardTrail`.
/// Reordering reuses the grid's drag and drop (`BoardGridDropDelegate` and
/// the board's `onReorder`), so the trail, the grid and the list all edit the
/// same manual order.
struct BoardTrailView: View {
    let board: Board
    let trail: BoardTrail
    let canReorder: Bool
    @Binding var selectedItem: Item?
    @Binding var openedItem: Item?
    @Binding var draggingItemID: UUID?
    var itemContextMenu: (Item) -> AnyView
    var onReorder: (UUID, UUID) -> Void

    /// Wide enough for a three-digit running number in `groveMeta`.
    @ScaledMetric(relativeTo: .caption) private var numberColumnWidth: CGFloat = 24
    /// Wide enough for the longest type label ("LECTURE") in the tracked
    /// section-header face.
    @ScaledMetric(relativeTo: .caption) private var typeColumnWidth: CGFloat = 60
    /// The same column when the type is marked with a symbol (Grove).
    @ScaledMetric(relativeTo: .caption) private var glyphColumnWidth: CGFloat = 20

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                masthead

                ForEach(Array(trail.entries.enumerated()), id: \.element.id) { index, entry in
                    switch entry {
                    case .source(let number, let item):
                        sourceRow(number: number, item: item, showsRule: isFollowedBySource(index))
                    case .note(let item):
                        noteBlock(item)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: trail.entries.map(\.id))
            .frame(maxWidth: RightRailMetrics.proseMeasure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LayoutDimensions.contentPaddingH)
            .padding(.vertical, Spacing.lg)
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: Spacing.xsm) {
            Text(board.title)
                .font(.groveTitle)
                .foregroundStyle(Color.textPrimary)

            if let description = BoardTrail.descriptionText(board.boardDescription) {
                Text(description)
                    .font(.groveGhostText)
                    .foregroundStyle(Color.textSecondary)
            }

            if !trail.countsLine.isEmpty {
                Text(trail.countsLine)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.lg)
    }

    // MARK: - Source Row

    private func sourceRow(number: Int, item: Item, showsRule: Bool) -> some View {
        Button {
            open(item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text("\(number)")
                    .font(.groveMeta)
                    .monospacedDigit()
                    .foregroundStyle(Color.textMuted)
                    .frame(width: numberColumnWidth, alignment: .trailing)

                // A symbol in Grove, a word in Commonplace; the column is
                // as wide as whichever the theme sets.
                ItemTypeMark(type: item.type, label: BoardTrail.typeLabel(for: item))
                    .frame(
                        width: ThemeStore.shared.theme.usesGlyphs ? glyphColumnWidth : typeColumnWidth,
                        alignment: .leading
                    )

                Text(item.title)
                    .font(.groveListTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let meta = BoardTrail.sourceMeta(for: item) {
                    Text(meta)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .selectedItemStyle(selectedItem?.id == item.id)
        .overlay(alignment: .bottom) {
            if showsRule {
                Rectangle()
                    .fill(Color.borderPrimary)
                    .frame(height: 1)
            }
        }
        .contextMenu { itemContextMenu(item) }
        .opacity(canReorder && draggingItemID == item.id ? 0.4 : 1)
        .onDrag {
            guard canReorder else { return NSItemProvider() }
            draggingItemID = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: BoardGridDropDelegate(
            targetItemID: item.id,
            draggingItemID: $draggingItemID,
            isEnabled: canReorder,
            onReorder: onReorder
        ))
    }

    /// A rule separates one source from the next. A source followed by a note
    /// (or by nothing) needs none: the note's card is the separation.
    private func isFollowedBySource(_ index: Int) -> Bool {
        let next = index + 1
        guard next < trail.entries.count else { return false }
        return trail.entries[next].isSource
    }

    // MARK: - Inline Note

    private func noteBlock(_ item: Item) -> some View {
        let title = noteTitle(for: item)
        let excerpt = BoardTrail.noteExcerpt(of: item.content)

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                open(item)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text("Note")
                            .font(.groveBadge)
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.textPrimary)
                        Text(noteDateLabel(item.createdAt))
                            .font(.groveMeta)
                            .foregroundStyle(Color.textMuted)
                    }

                    if let title {
                        Text(title)
                            .font(.groveItemTitle)
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.leading)
                    } else if excerpt.isEmpty {
                        Text("Untitled")
                            .font(.groveItemTitle)
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !excerpt.isEmpty {
                MarkdownTextView(markdown: excerpt, scale: .compact)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(BoardTrail.noteExcerptLineLimit)
            }

            Button {
                open(item)
            } label: {
                Text("Continue writing")
                    .font(.groveMeta)
                    .underline()
                    .foregroundStyle(Color.textSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open this note")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .selectedItemStyle(selectedItem?.id == item.id)
        // A card in Grove; between two rules in Commonplace.
        .entryStyle()
        .contextMenu { itemContextMenu(item) }
        // Notes hang from the type column, clear of the running numbers.
        .padding(.leading, Spacing.sm + numberColumnWidth + Spacing.md)
        .padding(.vertical, Spacing.sm)
        .opacity(canReorder && draggingItemID == item.id ? 0.4 : 1)
        .onDrag {
            guard canReorder else { return NSItemProvider() }
            draggingItemID = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: BoardGridDropDelegate(
            targetItemID: item.id,
            draggingItemID: $draggingItemID,
            isEnabled: canReorder,
            onReorder: onReorder
        ))
    }

    /// A note's own title, or nil while it still carries the placeholder an
    /// untitled note is stored under.
    private func noteTitle(for item: Item) -> String? {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != NoteDraft.untitledTitle else { return nil }
        return title
    }

    /// "17 Nov", with the year added once the note is from another year.
    private func noteDateLabel(_ date: Date) -> String {
        if Calendar.current.isDate(date, equalTo: Date.now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    // MARK: - Open

    private func open(_ item: Item) {
        selectedItem = item
        openedItem = item
    }
}
