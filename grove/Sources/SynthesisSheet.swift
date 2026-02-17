import SwiftUI
import SwiftData

/// Sheet for generating and previewing an AI synthesis note.
struct SynthesisSheet: View {
    let items: [Item]
    let scopeTitle: String
    let board: Board?
    let onCreated: (Item) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var synthesisService: SynthesisService?
    @State private var result: SynthesisResult?
    @State private var draftTitle: String = ""
    @State private var draftContent: String = ""
    @State private var isEditing = false
    @State private var hasGenerated = false

    private var itemCountWarning: Bool {
        items.count > 15
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let service = synthesisService, service.isGenerating {
                generatingView(service: service)
            } else if hasGenerated, result != nil {
                previewView
            } else if let service = synthesisService, let error = service.lastError {
                errorView(error: error)
            } else {
                scopeOverview
            }

            Divider()
            footer
        }
        .frame(width: 600, height: 550)
        .onAppear {
            synthesisService = SynthesisService(modelContext: modelContext)
            draftTitle = "Synthesis: \(scopeTitle)"
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text("Generate Synthesis")
                .font(.headline)
            Spacer()
            if let result {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                    Text(result.provider == .local ? "Local" : "API")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary)
                .clipShape(Capsule())
            }
        }
        .padding()
    }

    // MARK: - Scope Overview (before generation)

    private var scopeOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scope")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.purple)
                        Text(scopeTitle)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(items.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }

                if itemCountWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Large scope: \(items.count) items. Synthesis works best with 3–15 items. Results may be less focused.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .padding(10)
                    .background(.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Items list
                Text("Items to Synthesize")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ForEach(items.prefix(20)) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.type.iconName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(1)
                            if !item.tags.isEmpty {
                                Text(item.tags.prefix(3).map(\.name).joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text("\(item.annotations.count) notes")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if items.count > 20 {
                    Text("...and \(items.count - 20) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
        }
    }

    // MARK: - Generating

    private func generatingView(service: SynthesisService) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(service.progress)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.red)
            Text("Synthesis Failed")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Try Again") {
                startGeneration()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Preview (after generation)

    private var previewView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title field
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .font(.caption)
                TextField("Synthesis title", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    isEditing.toggle()
                } label: {
                    Label(isEditing ? "Preview" : "Edit", systemImage: isEditing ? "eye" : "pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            ScrollView {
                if isEditing {
                    TextEditor(text: $draftContent)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding()
                        .frame(minHeight: 300)
                } else {
                    MarkdownTextView(markdown: draftContent)
                        .padding()
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if hasGenerated && result != nil {
                Button("Regenerate") {
                    startGeneration()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Save Note") {
                    saveNote()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Generate Synthesis") {
                    startGeneration()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(synthesisService?.isGenerating == true)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func startGeneration() {
        guard let service = synthesisService else { return }
        hasGenerated = false
        result = nil

        Task {
            if let generated = await service.generateSynthesis(items: items, scopeTitle: scopeTitle) {
                await MainActor.run {
                    result = generated
                    draftContent = generated.markdownContent
                    hasGenerated = true
                }
            }
        }
    }

    private func saveNote() {
        guard let result, let service = synthesisService else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Synthesis: \(scopeTitle)"
            : draftTitle

        // If user edited the content, use the edited version
        var finalResult = result
        if draftContent != result.markdownContent {
            finalResult = SynthesisResult(
                markdownContent: draftContent,
                sourceItemIDs: result.sourceItemIDs,
                provider: result.provider
            )
        }

        let item = service.createSynthesisItem(from: finalResult, title: title, inBoard: board)
        onCreated(item)
        dismiss()
    }
}
