import SwiftUI
import SwiftData

struct BoardPackageImportSheet: View {
    let package: GrovePackage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [Item]
    @State private var previews: [ImportPreviewItem] = []
    @State private var importError: String?
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import Board")
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
                            if let icon = package.manifest.boardIcon {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(package.manifest.boardTitle)
                                    .font(.groveItemTitle)
                                    .foregroundStyle(Color.textPrimary)
                                if let desc = package.manifest.boardDescription, !desc.isEmpty {
                                    Text(desc)
                                        .font(.groveMeta)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }

                        HStack(spacing: Spacing.md) {
                            Text("\(package.manifest.itemCount) items")
                                .font(.groveMeta)
                                .foregroundStyle(Color.textTertiary)
                            if !package.reflections.isEmpty {
                                Text("\(package.reflections.count) reflections")
                                    .font(.groveMeta)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            if !package.connections.isEmpty {
                                Text("\(package.connections.count) connections")
                                    .font(.groveMeta)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }

                        Text("Exported \(package.manifest.exportDate.formatted(date: .long, time: .shortened))")
                            .font(.groveMeta)
                            .foregroundStyle(Color.textTertiary)
                    }

                    Divider()

                    // Items list
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("ITEMS")
                            .font(.groveBadge)
                            .tracking(0.8)
                            .foregroundStyle(Color.textTertiary)

                        ForEach(Array(previews.enumerated()), id: \.element.id) { index, preview in
                            importItemRow(preview: preview, index: index)
                        }
                    }

                    if let error = importError {
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

                let importCount = previews.filter { $0.decision != .skip }.count
                Button {
                    performImport()
                } label: {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Import \(importCount) items")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isImporting || importCount == 0)
            }
            .padding()
        }
        .frame(width: 500, height: 520)
        .onAppear {
            previews = BoardPackageService.buildImportPreview(
                package: package,
                existingItems: allItems
            )
        }
    }

    @ViewBuilder
    private func importItemRow(preview: ImportPreviewItem, index: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.transferItem.title)
                    .font(.groveBody)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                if preview.isNew {
                    Text("New")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    Text("Already exists (matched by URL)")
                        .font(.groveBadge)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()

            if preview.isNew {
                // New items: import or skip
                Picker("", selection: binding(for: index)) {
                    Text("Import").tag(ImportItemDecision.importAsNew)
                    Text("Skip").tag(ImportItemDecision.skip)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            } else {
                // Matched items: merge, new copy, or skip
                Picker("", selection: binding(for: index)) {
                    Text("Merge").tag(ImportItemDecision.mergeWithExisting)
                    Text("New").tag(ImportItemDecision.importAsNew)
                    Text("Skip").tag(ImportItemDecision.skip)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func binding(for index: Int) -> Binding<ImportItemDecision> {
        Binding(
            get: { previews[index].decision },
            set: { previews[index].decision = $0 }
        )
    }

    private func performImport() {
        isImporting = true
        importError = nil

        do {
            _ = try BoardPackageService.importPackage(
                package: package,
                decisions: previews,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
            isImporting = false
        }
    }
}
