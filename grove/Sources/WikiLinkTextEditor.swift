import SwiftUI
import SwiftData

/// A TextEditor wrapper that detects [[ wiki-link syntax and shows an autocomplete dropdown.
/// When a user selects an item from the dropdown, it inserts [[Item Title]] and auto-creates
/// a Connection of type .related between the current item and the linked item.
struct WikiLinkTextEditor: View {
    @Binding var text: String
    var sourceItem: Item?
    var placeholder: String = ""
    var minHeight: CGFloat = 80

    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]

    @State private var showWikiPopover = false
    @State private var wikiSearchText = ""
    @State private var cursorInsertionPoint: String.Index?

    private var wikiSearchResults: [Item] {
        allItems.filter { candidate in
            if let sourceItem, candidate.id == sourceItem.id { return false }
            if wikiSearchText.isEmpty { return true }
            return candidate.title.localizedCaseInsensitiveContains(wikiSearchText)
        }.prefix(10).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.blue.opacity(0.5), lineWidth: 1)
                )
                .onChange(of: text) { oldValue, newValue in
                    detectWikiLink(oldValue: oldValue, newValue: newValue)
                }

            if showWikiPopover {
                wikiLinkDropdown
            }
        }
    }

    private var wikiLinkDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Link to item")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showWikiPopover = false
                    wikiSearchText = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Divider()

            if wikiSearchResults.isEmpty {
                Text("No matching items")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(wikiSearchResults) { candidate in
                            Button {
                                insertWikiLink(for: candidate)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: candidate.type.iconName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 14)
                                    Text(candidate.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    private func detectWikiLink(oldValue: String, newValue: String) {
        // Check if the user just typed "[["
        guard newValue.count > oldValue.count else {
            // If user is deleting, check if wiki popover should close
            if showWikiPopover {
                updateWikiSearch()
            }
            return
        }

        if newValue.hasSuffix("[[") && !showWikiPopover {
            showWikiPopover = true
            wikiSearchText = ""
            return
        }

        if showWikiPopover {
            updateWikiSearch()
        }
    }

    private func updateWikiSearch() {
        // Find the last [[ in the text and extract search text after it
        guard let range = text.range(of: "[[", options: .backwards) else {
            showWikiPopover = false
            return
        }
        let afterBrackets = text[range.upperBound...]
        // If we find ]], the link is closed — hide popover
        if afterBrackets.contains("]]") {
            showWikiPopover = false
            return
        }
        wikiSearchText = String(afterBrackets)
    }

    private func insertWikiLink(for target: Item) {
        // Replace the partial [[search with [[Item Title]]
        guard let range = text.range(of: "[[", options: .backwards) else { return }
        let before = text[text.startIndex..<range.lowerBound]
        text = before + "[[" + target.title + "]]"

        // Auto-create a .related connection
        if let sourceItem {
            let viewModel = ItemViewModel(modelContext: modelContext)
            // Check if connection already exists
            let alreadyConnected = sourceItem.outgoingConnections.contains { $0.targetItem?.id == target.id }
                || sourceItem.incomingConnections.contains { $0.sourceItem?.id == target.id }
            if !alreadyConnected {
                _ = viewModel.createConnection(source: sourceItem, target: target, type: .related)
            }
        }

        showWikiPopover = false
        wikiSearchText = ""
    }
}
