import SwiftUI
import SwiftData

// MARK: - Item Export Sheet

struct ItemExportSheet: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss
    @State private var exportResult: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Item")
                    .font(.groveItemTitle)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Item") {
                    HStack(spacing: 6) {
                        Image(systemName: item.type.iconName)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 16)
                        Text(item.title)
                            .lineLimit(1)
                    }
                }

                Section {
                    Button("Export as Markdown (.md)") {
                        exportAsMarkdown()
                    }
                }

                if let result = exportResult {
                    Section {
                        Text(result)
                            .font(.groveBodySmall)
                            .foregroundStyle(Color.textPrimary)
                            .fontWeight(.medium)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding()
        }
        .frame(width: 420, height: 280)
    }

    private func exportAsMarkdown() {
        #if os(macOS)
        guard let url = ExportService.showSavePanel(filename: item.title) else { return }

        guard let data = ExportService.exportItem(item) else {
            exportResult = "Export failed."
            return
        }

        do {
            try data.write(to: url)
            exportResult = "Exported to \(url.lastPathComponent)"
            Task { try? await Task.sleep(for: .seconds(1)); dismiss() }
        } catch {
            exportResult = "Error: \(error.localizedDescription)"
        }
        #else
        exportResult = "Export not yet available on iOS."
        #endif
    }
}
