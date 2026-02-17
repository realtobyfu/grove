import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Board Export Sheet

struct BoardExportSheet: View {
    let board: Board
    let items: [Item]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .markdown
    @State private var exportResult: String?
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Board")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Board") {
                    HStack {
                        if let icon = board.icon {
                            Image(systemName: icon)
                                .foregroundStyle(.secondary)
                        }
                        Text(board.title)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(items.count) items")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Format") {
                    Picker("Export Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Send to Obsidian") {
                    HStack {
                        Text("Export each item as a separate .md file to your Obsidian vault.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Send") {
                            sendToObsidian()
                        }
                        .disabled(ExportSettings.obsidianFolderPath == nil || ExportSettings.obsidianFolderPath?.isEmpty == true)
                    }

                    if ExportSettings.obsidianFolderPath == nil || ExportSettings.obsidianFolderPath?.isEmpty == true {
                        Text("Configure your Obsidian vault path in Settings → Export first.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let result = exportResult {
                    Section {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Export") {
                    exportBoard()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting)
            }
            .padding()
        }
        .frame(width: 460, height: 440)
    }

    private func exportBoard() {
        guard let url = ExportService.showSavePanel(
            title: "Export \(board.title)",
            filename: board.title,
            format: selectedFormat
        ) else { return }

        guard let data = ExportService.exportBoard(board, items: items, format: selectedFormat) else {
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
    }

    private func sendToObsidian() {
        if ExportService.sendBoardToObsidian(board, items: items) {
            exportResult = "Sent \(items.count) items to Obsidian vault."
        } else {
            exportResult = "Failed to send to Obsidian. Check your vault path in Settings."
        }
    }
}

// MARK: - Item Export Sheet

struct ItemExportSheet: View {
    let items: [Item]
    @Environment(\.dismiss) private var dismiss
    @State private var exportResult: String?

    var isBatch: Bool { items.count > 1 }
    var title: String { isBatch ? "Export \(items.count) Items" : "Export Item" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Items") {
                    ForEach(items.prefix(10)) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.type.iconName)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(item.title)
                                .lineLimit(1)
                        }
                    }
                    if items.count > 10 {
                        Text("... and \(items.count - 10) more")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Section("Actions") {
                    Button("Export as Markdown (.md)") {
                        exportAsMarkdown()
                    }

                    if isBatch {
                        Button("Export as ZIP") {
                            exportAsZip()
                        }
                    }

                    Button("Send to Obsidian") {
                        sendToObsidian()
                    }
                    .disabled(ExportSettings.obsidianFolderPath == nil || ExportSettings.obsidianFolderPath?.isEmpty == true)

                    if ExportSettings.obsidianFolderPath == nil || ExportSettings.obsidianFolderPath?.isEmpty == true {
                        Text("Configure your Obsidian vault path in Settings → Export first.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let result = exportResult {
                    Section {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.green)
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
        .frame(width: 420, height: isBatch ? 420 : 340)
    }

    private func exportAsMarkdown() {
        let filename = isBatch ? "export-\(items.count)-items" : items.first?.title ?? "item"
        guard let url = ExportService.showSavePanel(
            title: "Export as Markdown",
            filename: filename,
            format: .markdown
        ) else { return }

        let data: Data?
        if isBatch {
            data = ExportService.exportItems(items)
        } else if let item = items.first {
            data = ExportService.exportItem(item)
        } else {
            return
        }

        guard let data else {
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
    }

    private func exportAsZip() {
        guard let url = ExportService.showSavePanelForZip(filename: "grove-export") else { return }
        if ExportService.exportItemsAsZip(items, to: url) {
            exportResult = "Exported \(items.count) items to \(url.lastPathComponent)"
            Task { try? await Task.sleep(for: .seconds(1)); dismiss() }
        } else {
            exportResult = "ZIP export failed."
        }
    }

    private func sendToObsidian() {
        if ExportService.sendItemsToObsidian(items) {
            exportResult = "Sent \(items.count) item\(items.count == 1 ? "" : "s") to Obsidian vault."
        } else {
            exportResult = "Failed. Check your Obsidian vault path in Settings."
        }
    }
}

// MARK: - Export Settings View

struct ExportSettingsView: View {
    @State private var obsidianPath: String = ExportSettings.obsidianFolderPath ?? ""

    var body: some View {
        Form {
            Section("Obsidian Integration") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vault export folder path:")
                        .font(.subheadline)

                    HStack {
                        TextField("/path/to/obsidian/vault", text: $obsidianPath)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: obsidianPath) {
                                ExportSettings.obsidianFolderPath = obsidianPath.isEmpty ? nil : obsidianPath
                            }

                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.canCreateDirectories = true
                            panel.title = "Select Obsidian Vault Folder"
                            if panel.runModal() == .OK, let url = panel.url {
                                obsidianPath = url.path
                                ExportSettings.obsidianFolderPath = url.path
                            }
                        }
                    }

                    Text("Items exported to Obsidian will be saved as individual .md files in this folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Formats") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Supported export formats:")
                        .font(.subheadline)
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(format.rawValue)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
