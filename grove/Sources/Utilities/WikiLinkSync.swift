import Foundation
import SwiftData

/// Ensures a `.related` Connection exists for every `[[Wiki Link]]` found in an
/// item's markdown content.
///
/// The autocomplete dropdown in `RichMarkdownEditor`/`WikiLinkTextEditor` only
/// creates a Connection when a target is picked from the dropdown AND the editor
/// has a non-nil `sourceItem`. Links that are typed manually — or written in a
/// context without a source item (e.g. the global Write panel) — never become
/// connections. Running this sync at save points closes that gap.
///
/// Design decisions:
/// - **Additive only.** Removing a `[[link]]` from the text does NOT delete the
///   corresponding Connection. Connections can also be created manually via the
///   Inspector, from chat, and by suggestion services — deleting on text removal
///   would destroy edges the user created through other flows. Stale edges can
///   be removed by hand in the Inspector.
/// - **Title matching is case-insensitive exact** (`localizedCaseInsensitiveCompare`),
///   the same rule used by wiki-link tap navigation (`ItemReaderViewModel` /
///   `DialecticalChatViewModel.navigateToItemByTitle`). `ItemResolver` was
///   considered but not used: its unique-substring fallback is appropriate for
///   resolving an explicit user tap, but too loose for silently creating graph
///   edges on every save.
/// - **Link syntax matches the renderer.** Titles are extracted with the same
///   pattern `MarkdownDocument` uses for `.wikiLink` spans (`\[\[(.+?)\]\]`).
///   The codebase has no `[[Title|alias]]` syntax — the renderer treats the whole
///   inner text as the title, and so does this parser.
@MainActor
enum WikiLinkSync {
    /// Extracts the titles of all `[[...]]` wiki-links in the given markdown.
    /// Mirrors MarkdownDocument's inline wiki-link pattern exactly.
    static func linkTitles(in markdown: String) -> [String] {
        guard markdown.contains("[["),
              let regex = try? NSRegularExpression(pattern: #"\[\[(.+?)\]\]"#) else {
            return []
        }
        let nsText = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsText.length))

        var seen = Set<String>()
        var titles: [String] = []
        for match in matches where match.numberOfRanges > 1 {
            let title = nsText.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let key = title.lowercased()
            if seen.insert(key).inserted {
                titles.append(title)
            }
        }
        return titles
    }

    /// Ensures a `.related` Connection exists from `item` to every existing item
    /// referenced by a `[[Wiki Link]]` in `content`.
    ///
    /// - Parameters:
    ///   - item: The source item the links were written in.
    ///   - content: Markdown to scan. Defaults to `item.content` when nil.
    ///   - modelContext: Context used to resolve targets and persist connections.
    static func sync(item: Item, content: String? = nil, modelContext: ModelContext) {
        let markdown = content ?? item.content ?? ""
        let titles = linkTitles(in: markdown)
        guard !titles.isEmpty else { return }

        let allItems: [Item] = modelContext.fetchAll()
        let viewModel = ItemViewModel(modelContext: modelContext)

        for title in titles {
            guard let target = ItemResolver.resolveExactTitle(title, in: allItems, excluding: item.id) else { continue }

            // Dedupe in either direction — same check as the autocomplete path.
            let alreadyConnected = item.outgoingConnections.contains { $0.targetItem?.id == target.id }
                || item.incomingConnections.contains { $0.sourceItem?.id == target.id }
            if !alreadyConnected {
                _ = viewModel.createConnection(source: item, target: target, type: .related)
            }
        }
    }
}
