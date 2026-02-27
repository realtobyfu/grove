import SwiftUI

struct BoardPackageExportSheet: View {
    let board: Board
    let items: [Item]
    @State private var options = BoardExportOptions()
    @State private var isExporting = false
    @State private var exportError: String?
    @Environment(\.dismiss) private var dismiss

    private var connectionCountExcluded: Int {
        let boardItemIDs = Set(items.map(\.id))
        var excluded = 0
        for item in items {
            excluded += item.outgoingConnections.filter {
                guard let targetID = $0.targetItem?.id else { return true }
                return !boardItemIDs.contains(targetID)
            }.count
            excluded += item.incomingConnections.filter {
                guard let sourceID = $0.sourceItem?.id else { return true }
                return !boardItemIDs.contains(sourceID)
            }.count
        }
        return excluded
    }

    private var connectionCountIncluded: Int {
        guard options.includeConnections else { return 0 }
        let boardItemIDs = Set(items.map(\.id))
        var seen = Set<UUID>()
        for item in items {
            for conn in item.outgoingConnections + item.incomingConnections {
                guard !seen.contains(conn.id),
                      let sourceID = conn.sourceItem?.id,
                      let targetID = conn.targetItem?.id,
                      boardItemIDs.contains(sourceID),
                      boardItemIDs.contains(targetID) else { continue }
                seen.insert(conn.id)
            }
        }
        return seen.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Board Package")
                    .font(.groveItemTitle)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Board info
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.sm) {
                            if let icon = board.icon {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(board.title)
                                    .font(.groveItemTitle)
                                    .foregroundStyle(Color.textPrimary)
                                if let desc = board.boardDescription, !desc.isEmpty {
                                    Text(desc)
                                        .font(.groveMeta)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                        Text("\(items.count) items")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }

                    Divider()

                    // Privacy toggles
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("INCLUDE IN EXPORT")
                            .font(.groveBadge)
                            .tracking(0.8)
                            .foregroundStyle(Color.textTertiary)

                        VStack(spacing: Spacing.xs) {
                            HStack {
                                Text("Items (titles + sources)")
                                    .font(.groveBody)
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Text("Always included")
                                    .font(.groveMeta)
                                    .foregroundStyle(Color.textTertiary)
                            }

                            Toggle("Reflections", isOn: $options.includeReflections)
                                .font(.groveBody)

                            Toggle("Full item content", isOn: $options.includeContent)
                                .font(.groveBody)

                            Toggle("Connections", isOn: $options.includeConnections)
                                .font(.groveBody)

                            Toggle("Tags", isOn: $options.includeTags)
                                .font(.groveBody)
                        }
                    }

                    // Info notes
                    if options.includeConnections && connectionCountExcluded > 0 {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                            Text("\(connectionCountExcluded) connections to items outside this board will be excluded. \(connectionCountIncluded) connections included.")
                                .font(.groveMeta)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    if let error = exportError {
                        Text(error)
                            .font(.groveMeta)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    performExport()
                } label: {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Export .grove")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting)
            }
            .padding()
        }
        .frame(width: 440, height: 460)
    }

    private func performExport() {
        #if os(macOS)
        guard let saveURL = BoardPackageService.showExportSavePanel(boardTitle: board.title) else {
            return
        }
        isExporting = true
        exportError = nil

        do {
            let data = try BoardPackageService.exportPackage(
                board: board,
                items: items,
                options: options
            )
            try data.write(to: saveURL)
            dismiss()
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
            isExporting = false
        }
        #endif
    }
}
