import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - Export Service

/// Protocol for export service.
@MainActor
protocol ExportServiceProtocol {
    static func exportItem(_ item: Item) -> Data?
    static func markdownForItem(_ item: Item) -> String
}

@MainActor
final class ExportService: ExportServiceProtocol {

    // MARK: - Item Export

    static func exportItem(_ item: Item) -> Data? {
        return markdownForItem(item).data(using: .utf8)
    }

    // MARK: - Save Panel

    #if os(macOS)
    static func showSavePanel(filename: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export as Markdown"
        panel.nameFieldStringValue = sanitizeFilename(filename) + ".md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
    #endif

    // MARK: - Markdown Generation

    static func markdownForItem(_ item: Item) -> String {
        var md = "# \(item.title)\n\n"

        // Metadata
        md += "**Type:** \(item.type.rawValue.capitalized)  \n"
        md += "**Status:** \(item.status.rawValue.capitalized)  \n"
        md += "**Created:** \(item.createdAt.formatted(date: .long, time: .shortened))  \n"
        md += "**Updated:** \(item.updatedAt.formatted(date: .long, time: .shortened))  \n"

        if let url = item.sourceURL, !url.isEmpty {
            md += "**Source:** [\(url)](\(url))  \n"
        }

        // Tags
        if !item.tags.isEmpty {
            md += "**Tags:** \(item.tags.map { "#\($0.name)" }.joined(separator: ", "))  \n"
        }

        // Boards
        if !item.boards.isEmpty {
            md += "**Boards:** \(item.boards.map(\.title).joined(separator: ", "))  \n"
        }

        md += "\n"

        // Content
        if let content = item.content, !content.isEmpty {
            md += "## Content\n\n"
            md += content + "\n\n"
        }

        // Reflections
        if !item.reflections.isEmpty {
            md += "## Reflections\n\n"
            for block in item.reflections.sorted(by: { $0.position < $1.position }) {
                md += "### \(block.blockType.displayName) — \(block.createdAt.formatted(date: .abbreviated, time: .shortened))\n\n"
                if let ts = block.videoTimestamp {
                    md += "*Timestamp: \(Double(ts).formattedTimestamp)*\n\n"
                }
                if let highlight = block.highlight, !highlight.isEmpty {
                    md += "> \(highlight)\n\n"
                }
                md += block.content + "\n\n"
            }
        }

        // Connections
        let allConnections = item.outgoingConnections + item.incomingConnections
        if !allConnections.isEmpty {
            md += "## Connections\n\n"
            for conn in allConnections {
                let isOutgoing = conn.sourceItem?.id == item.id
                let linkedItem = isOutgoing ? conn.targetItem : conn.sourceItem
                let direction = isOutgoing ? "→" : "←"
                md += "- \(direction) **\(conn.type.displayLabel)**: \(linkedItem?.title ?? "Unknown")\n"
            }
            md += "\n"
        }

        return md
    }

    // MARK: - Helpers

    private static func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
}
