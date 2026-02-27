import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Export Options

struct BoardExportOptions: Sendable {
    var includeReflections: Bool = true
    var includeContent: Bool = false
    var includeConnections: Bool = false
    var includeTags: Bool = false
}

// MARK: - Board Export Service

@MainActor
final class BoardExportService {

    // MARK: - Markdown Generation

    static func markdownForBoard(_ board: Board, items: [Item], options: BoardExportOptions) -> String {
        var md = "# \(board.title)\n\n"

        if let desc = board.boardDescription, !desc.isEmpty {
            md += "\(desc)\n\n"
        }

        md += "**Items:** \(items.count)  \n"
        md += "**Exported:** \(Date.now.formatted(date: .long, time: .shortened))  \n"
        md += "\n---\n\n"

        for (index, item) in items.enumerated() {
            md += "## \(index + 1). \(item.title)\n\n"

            md += "**Type:** \(item.type.rawValue.capitalized)  \n"

            if let url = item.sourceURL, !url.isEmpty {
                md += "**Source:** [\(url)](\(url))  \n"
            }

            if options.includeTags && !item.tags.isEmpty {
                md += "**Tags:** \(item.tags.map { "#\($0.name)" }.joined(separator: ", "))  \n"
            }

            md += "\n"

            if options.includeContent, let content = item.content, !content.isEmpty {
                md += "### Content\n\n"
                md += content + "\n\n"
            }

            if options.includeReflections && !item.reflections.isEmpty {
                md += "### Reflections\n\n"
                for block in item.reflections.sorted(by: { $0.position < $1.position }) {
                    md += "**\(block.blockType.displayName)**"
                    if let ts = block.videoTimestamp {
                        md += " (\(Double(ts).formattedTimestamp))"
                    }
                    md += "\n\n"
                    if let highlight = block.highlight, !highlight.isEmpty {
                        md += "> \(highlight)\n\n"
                    }
                    md += block.content + "\n\n"
                }
            }

            if options.includeConnections {
                let boardItemIDs = Set(items.map(\.id))
                let outgoing = item.outgoingConnections.filter {
                    guard let targetID = $0.targetItem?.id else { return false }
                    return boardItemIDs.contains(targetID)
                }
                let incoming = item.incomingConnections.filter {
                    guard let sourceID = $0.sourceItem?.id else { return false }
                    return boardItemIDs.contains(sourceID)
                }
                let connections = outgoing + incoming
                if !connections.isEmpty {
                    md += "### Connections\n\n"
                    for conn in connections {
                        let isOutgoing = conn.sourceItem?.id == item.id
                        let linkedItem = isOutgoing ? conn.targetItem : conn.sourceItem
                        let direction = isOutgoing ? "\u{2192}" : "\u{2190}"
                        md += "- \(direction) **\(conn.type.displayLabel)**: \(linkedItem?.title ?? "Unknown")\n"
                    }
                    md += "\n"
                }
            }

            if index < items.count - 1 {
                md += "---\n\n"
            }
        }

        return md
    }

    // MARK: - Clipboard

    static func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    // MARK: - Sharing Service

    #if os(macOS)
    static func share(_ text: String, from view: NSView) {
        let picker = NSSharingServicePicker(items: [text])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
    #endif
}
