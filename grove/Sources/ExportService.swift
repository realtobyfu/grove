import Foundation
import AppKit
import PDFKit

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Sendable {
    case markdown = "Markdown (.md)"
    case pdf = "PDF (.pdf)"
    case opml = "OPML (.opml)"
    case html = "Static HTML (.html)"

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .pdf: "pdf"
        case .opml: "opml"
        case .html: "html"
        }
    }

    var utType: String {
        switch self {
        case .markdown: "net.daringfireball.markdown"
        case .pdf: "com.adobe.pdf"
        case .opml: "org.opml.opml"
        case .html: "public.html"
        }
    }
}

// MARK: - Export Settings

struct ExportSettings {
    static let obsidianFolderKey = "groveObsidianFolderPath"

    static var obsidianFolderPath: String? {
        get { UserDefaults.standard.string(forKey: obsidianFolderKey) }
        set { UserDefaults.standard.set(newValue, forKey: obsidianFolderKey) }
    }
}

// MARK: - Export Service

@MainActor
final class ExportService {

    // MARK: - Board Export

    static func exportBoard(_ board: Board, items: [Item], format: ExportFormat) -> Data? {
        switch format {
        case .markdown:
            return markdownForBoard(board, items: items).data(using: .utf8)
        case .pdf:
            return pdfForBoard(board, items: items)
        case .opml:
            return opmlForBoard(board, items: items).data(using: .utf8)
        case .html:
            return htmlForBoard(board, items: items).data(using: .utf8)
        }
    }

    // MARK: - Item Export

    static func exportItem(_ item: Item) -> Data? {
        return markdownForItem(item).data(using: .utf8)
    }

    static func exportItems(_ items: [Item]) -> Data? {
        let combined = items.map { markdownForItem($0) }.joined(separator: "\n\n---\n\n")
        return combined.data(using: .utf8)
    }

    // MARK: - Send to Obsidian

    static func sendBoardToObsidian(_ board: Board, items: [Item]) -> Bool {
        guard let folderPath = ExportSettings.obsidianFolderPath, !folderPath.isEmpty else { return false }
        let folderURL = URL(fileURLWithPath: folderPath)

        let fm = FileManager.default
        // Create the board subfolder
        let boardFolderURL = folderURL.appendingPathComponent(sanitizeFilename(board.title))
        try? fm.createDirectory(at: boardFolderURL, withIntermediateDirectories: true)

        // Export each item as a separate .md file
        for item in items {
            let content = markdownForItem(item)
            let filename = sanitizeFilename(item.title) + ".md"
            let fileURL = boardFolderURL.appendingPathComponent(filename)
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return true
    }

    static func sendItemsToObsidian(_ items: [Item]) -> Bool {
        guard let folderPath = ExportSettings.obsidianFolderPath, !folderPath.isEmpty else { return false }
        let folderURL = URL(fileURLWithPath: folderPath)

        let fm = FileManager.default
        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        for item in items {
            let content = markdownForItem(item)
            let filename = sanitizeFilename(item.title) + ".md"
            let fileURL = folderURL.appendingPathComponent(filename)
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return true
    }

    // MARK: - Save Panel Helpers

    static func showSavePanel(title: String, filename: String, format: ExportFormat) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = sanitizeFilename(filename) + "." + format.fileExtension
        panel.allowedContentTypes = [.init(filenameExtension: format.fileExtension) ?? .data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func showSavePanelForZip(filename: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Items"
        panel.nameFieldStringValue = sanitizeFilename(filename) + ".zip"
        panel.allowedContentTypes = [.init(filenameExtension: "zip") ?? .data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: - Batch Export as Zip

    static func exportItemsAsZip(_ items: [Item], to url: URL) -> Bool {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for item in items {
            let content = markdownForItem(item)
            let filename = sanitizeFilename(item.title) + ".md"
            let fileURL = tempDir.appendingPathComponent(filename)
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Create zip using ditto
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", tempDir.path, url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        try? FileManager.default.removeItem(at: tempDir)
        return process.terminationStatus == 0
    }

    // MARK: - Markdown Generation

    static func markdownForBoard(_ board: Board, items: [Item]) -> String {
        var md = "# \(board.title)\n\n"

        if let desc = board.boardDescription, !desc.isEmpty {
            md += "> \(desc)\n\n"
        }

        md += "**Items:** \(items.count)  \n"
        md += "**Exported:** \(Date.now.formatted(date: .long, time: .shortened))\n\n"
        md += "---\n\n"

        for item in items.sorted(by: { $0.createdAt > $1.createdAt }) {
            md += markdownForItemInBoard(item)
            md += "\n---\n\n"
        }

        return md
    }

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

        // Annotations
        if !item.annotations.isEmpty {
            md += "## Annotations\n\n"
            for annotation in item.annotations.sorted(by: { $0.createdAt < $1.createdAt }) {
                md += "### \(annotation.createdAt.formatted(date: .abbreviated, time: .shortened))\n\n"
                md += annotation.content + "\n\n"
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

    private static func markdownForItemInBoard(_ item: Item) -> String {
        var md = "## \(item.title)\n\n"

        md += "**Type:** \(item.type.rawValue.capitalized)  \n"

        if let url = item.sourceURL, !url.isEmpty {
            md += "**Source:** [\(url)](\(url))  \n"
        }

        if !item.tags.isEmpty {
            md += "**Tags:** \(item.tags.map { "#\($0.name)" }.joined(separator: ", "))  \n"
        }

        md += "**Added:** \(item.createdAt.formatted(date: .abbreviated, time: .omitted))  \n"
        md += "\n"

        if let content = item.content, !content.isEmpty {
            md += content + "\n\n"
        }

        // Annotations
        if !item.annotations.isEmpty {
            md += "### Annotations\n\n"
            for annotation in item.annotations.sorted(by: { $0.createdAt < $1.createdAt }) {
                md += "> \(annotation.content)\n"
                md += "> — *\(annotation.createdAt.formatted(date: .abbreviated, time: .shortened))*\n\n"
            }
        }

        // Connections
        let allConnections = item.outgoingConnections + item.incomingConnections
        if !allConnections.isEmpty {
            md += "### Connections\n\n"
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

    // MARK: - PDF Generation

    static func pdfForBoard(_ board: Board, items: [Item]) -> Data? {
        let markdown = markdownForBoard(board, items: items)

        // Use NSAttributedString for PDF rendering
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.textColor
        ]

        let attrString = NSMutableAttributedString(string: markdown, attributes: attrs)

        // Style headers
        styleMarkdownHeaders(in: attrString)

        // Create PDF via text view rendering
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 10000))
        textView.textStorage?.setAttributedString(attrString)
        textView.sizeToFit()

        let printInfo = NSPrintInfo()
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.paperSize = NSSize(width: 612, height: 792) // US Letter

        let printableWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let printableHeight = printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin

        textView.frame = NSRect(x: 0, y: 0, width: printableWidth, height: 10000)
        textView.textContainer?.containerSize = NSSize(width: printableWidth, height: .greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
        let totalHeight = usedRect.height

        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: printInfo.paperSize.width, height: printInfo.paperSize.height)

        var consumer: CGDataConsumer?
        consumer = CGDataConsumer(data: pdfData as CFMutableData)
        guard let dataConsumer = consumer,
              var context = CGContext(consumer: dataConsumer, mediaBox: nil, nil) else {
            return nil
        }

        var yOffset: CGFloat = 0
        while yOffset < totalHeight {
            var mediaBox = pageRect
            context.beginPage(mediaBox: &mediaBox)

            context.translateBy(x: printInfo.leftMargin, y: printInfo.bottomMargin)

            // Clip to printable area
            context.clip(to: CGRect(x: 0, y: 0, width: printableWidth, height: printableHeight))

            // Draw text at proper offset
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.current = graphicsContext

            context.translateBy(x: 0, y: printableHeight + yOffset)
            context.scaleBy(x: 1, y: -1)

            textView.layoutManager?.drawGlyphs(forGlyphRange: NSRange(location: 0, length: textView.textStorage?.length ?? 0), at: .zero)

            NSGraphicsContext.current = nil
            context.endPage()

            yOffset += printableHeight
        }

        context.closePDF()
        return pdfData as Data
    }

    private static func styleMarkdownHeaders(in attrString: NSMutableAttributedString) {
        let text = attrString.string as NSString
        let lines = text.components(separatedBy: "\n")
        var pos = 0
        for line in lines {
            let lineLen = (line as NSString).length
            let range = NSRange(location: pos, length: lineLen)

            if line.hasPrefix("# ") {
                attrString.addAttributes([
                    .font: NSFont.systemFont(ofSize: 22, weight: .bold)
                ], range: range)
            } else if line.hasPrefix("## ") {
                attrString.addAttributes([
                    .font: NSFont.systemFont(ofSize: 17, weight: .semibold)
                ], range: range)
            } else if line.hasPrefix("### ") {
                attrString.addAttributes([
                    .font: NSFont.systemFont(ofSize: 14, weight: .medium)
                ], range: range)
            } else if line.hasPrefix("**") && line.hasSuffix("**") {
                attrString.addAttributes([
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                ], range: range)
            }

            pos += lineLen + 1 // +1 for \n
        }
    }

    // MARK: - OPML Generation

    static func opmlForBoard(_ board: Board, items: [Item]) -> String {
        var opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>\(escapeXML(board.title))</title>
            <dateCreated>\(Date.now.formatted(.iso8601))</dateCreated>
          </head>
          <body>
        """

        for item in items.sorted(by: { $0.createdAt > $1.createdAt }) {
            let url = item.sourceURL ?? ""
            opml += """
                <outline text="\(escapeXML(item.title))" type="\(item.type.rawValue)" htmlUrl="\(escapeXML(url))">
            """

            // Annotations as sub-outlines
            for annotation in item.annotations.sorted(by: { $0.createdAt < $1.createdAt }) {
                let preview = String(annotation.content.prefix(200))
                opml += """
                      <outline text="\(escapeXML(preview))" type="annotation" />
                """
            }

            opml += """
                </outline>
            """
        }

        opml += """
          </body>
        </opml>
        """

        return opml
    }

    // MARK: - HTML Generation

    static func htmlForBoard(_ board: Board, items: [Item]) -> String {
        let boardColor = board.color ?? "#6366F1"
        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>\(escapeHTML(board.title)) — Grove</title>
          <style>
            :root { --accent: \(boardColor); }
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
              background: #1a1a1a; color: #e0e0e0;
              max-width: 800px; margin: 0 auto; padding: 40px 20px;
              line-height: 1.6;
            }
            h1 { font-size: 2em; margin-bottom: 8px; color: #fff; }
            .meta { color: #888; font-size: 0.85em; margin-bottom: 32px; }
            .item { background: #252525; border-radius: 12px; padding: 24px; margin-bottom: 20px; border: 1px solid #333; }
            .item h2 { font-size: 1.3em; color: #fff; margin-bottom: 8px; }
            .item .item-meta { color: #888; font-size: 0.8em; margin-bottom: 12px; }
            .item .item-meta a { color: var(--accent); text-decoration: none; }
            .item .item-meta a:hover { text-decoration: underline; }
            .tags { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 12px; }
            .tag { background: #333; color: #bbb; padding: 2px 10px; border-radius: 99px; font-size: 0.75em; }
            .content { white-space: pre-wrap; font-size: 0.95em; margin-bottom: 16px; }
            .annotation { background: #1e1e1e; border-left: 3px solid var(--accent); padding: 12px 16px; margin: 8px 0; border-radius: 4px; }
            .annotation .date { color: #666; font-size: 0.75em; }
            .connections { font-size: 0.85em; color: #999; }
            .connections span { color: var(--accent); }
            hr { border: none; border-top: 1px solid #333; margin: 32px 0; }
            .footer { text-align: center; color: #555; font-size: 0.75em; margin-top: 40px; }
          </style>
        </head>
        <body>
          <h1>\(escapeHTML(board.title))</h1>
          <p class="meta">\(items.count) items &middot; Exported \(Date.now.formatted(date: .long, time: .shortened))</p>
        """

        for item in items.sorted(by: { $0.createdAt > $1.createdAt }) {
            html += "<div class=\"item\">"
            html += "<h2>\(escapeHTML(item.title))</h2>"

            var meta: [String] = []
            meta.append(item.type.rawValue.capitalized)
            meta.append(item.createdAt.formatted(date: .abbreviated, time: .omitted))
            if let url = item.sourceURL, !url.isEmpty {
                meta.append("<a href=\"\(escapeHTML(url))\">\(escapeHTML(url))</a>")
            }
            html += "<p class=\"item-meta\">\(meta.joined(separator: " &middot; "))</p>"

            if !item.tags.isEmpty {
                html += "<div class=\"tags\">"
                for tag in item.tags {
                    html += "<span class=\"tag\">#\(escapeHTML(tag.name))</span>"
                }
                html += "</div>"
            }

            if let content = item.content, !content.isEmpty {
                html += "<div class=\"content\">\(escapeHTML(content))</div>"
            }

            if !item.annotations.isEmpty {
                for annotation in item.annotations.sorted(by: { $0.createdAt < $1.createdAt }) {
                    html += "<div class=\"annotation\">"
                    html += "<p>\(escapeHTML(annotation.content))</p>"
                    html += "<p class=\"date\">\(annotation.createdAt.formatted(date: .abbreviated, time: .shortened))</p>"
                    html += "</div>"
                }
            }

            let allConnections = item.outgoingConnections + item.incomingConnections
            if !allConnections.isEmpty {
                html += "<div class=\"connections\">"
                for conn in allConnections {
                    let isOutgoing = conn.sourceItem?.id == item.id
                    let linkedItem = isOutgoing ? conn.targetItem : conn.sourceItem
                    let dir = isOutgoing ? "→" : "←"
                    html += "<p>\(dir) <span>\(escapeHTML(conn.type.displayLabel))</span>: \(escapeHTML(linkedItem?.title ?? "Unknown"))</p>"
                }
                html += "</div>"
            }

            html += "</div>"
        }

        html += """
          <p class="footer">Exported from Grove</p>
        </body>
        </html>
        """

        return html
    }

    // MARK: - Helpers

    private static func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func escapeHTML(_ string: String) -> String {
        escapeXML(string)
    }
}
