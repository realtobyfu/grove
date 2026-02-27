import SwiftUI

struct BoardShareMenu: View {
    let board: Board
    let items: [Item]
    @State private var options = BoardExportOptions()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("SHARE BOARD")
                .sectionHeaderStyle()
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(board.title)
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("\(items.count) items")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, Spacing.md)

            Divider()

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("INCLUDE")
                    .font(.groveBadge)
                    .tracking(0.8)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, Spacing.md)

                Toggle("Reflections", isOn: $options.includeReflections)
                    .font(.groveBody)
                    .padding(.horizontal, Spacing.md)

                Toggle("Full item content", isOn: $options.includeContent)
                    .font(.groveBody)
                    .padding(.horizontal, Spacing.md)

                Toggle("Connections", isOn: $options.includeConnections)
                    .font(.groveBody)
                    .padding(.horizontal, Spacing.md)

                Toggle("Tags", isOn: $options.includeTags)
                    .font(.groveBody)
                    .padding(.horizontal, Spacing.md)
            }

            Divider()

            VStack(spacing: Spacing.sm) {
                Button {
                    let md = BoardExportService.markdownForBoard(board, items: items, options: options)
                    BoardExportService.copyToClipboard(md)
                    dismiss()
                } label: {
                    Label("Copy as Markdown", systemImage: "doc.on.doc")
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                #if os(macOS)
                Button {
                    let md = BoardExportService.markdownForBoard(board, items: items, options: options)
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(sanitizeFilename(board.title))
                        .appendingPathExtension("md")
                    try? md.data(using: .utf8)?.write(to: tempURL)
                    let picker = NSSharingServicePicker(items: [tempURL])
                    if let window = NSApp.keyWindow, let contentView = window.contentView {
                        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                    }
                    dismiss()
                } label: {
                    Label("Share...", systemImage: "square.and.arrow.up")
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                #else
                ShareLink(item: BoardExportService.markdownForBoard(board, items: items, options: options)) {
                    Label("Share...", systemImage: "square.and.arrow.up")
                        .font(.groveBody)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.borderPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                #endif
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
        .frame(width: 280)
        .background(Color.bgInspector)
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
}
