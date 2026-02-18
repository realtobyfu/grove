import SwiftUI
import SwiftData

/// Sheet for generating and previewing an AI synthesis note.
/// Auto-starts generation on appear — no extra click needed.
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
                // Brief generating placeholder while service initializes
                generatingPlaceholder
            }

            Divider()
            footer
        }
        .frame(width: 600, height: 550)
        .background(Color.bgPrimary)
        .onAppear {
            synthesisService = SynthesisService(modelContext: modelContext)
            draftTitle = "Synthesis: \(scopeTitle)"
            startGeneration()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("SYNTHESIS")
                .font(.groveSectionHeader)
                .tracking(1.2)
                .foregroundStyle(Color.textMuted)

            Spacer()

            if let result, hasGenerated {
                HStack(spacing: 4) {
                    Image(systemName: result.isLLMGenerated ? "sparkles" : "cpu")
                        .font(.system(size: 9))
                    Text(result.isLLMGenerated ? "AI Draft" : "Local")
                        .font(.groveBadge)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentBadge)
                .clipShape(Capsule())
            }

            Text("\(items.count) items")
                .font(.groveBadge)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentBadge)
                .clipShape(Capsule())
        }
        .padding()
    }

    // MARK: - Generating Placeholder (before service initializes)

    private var generatingPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Preparing synthesis...")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Generating

    private func generatingView(service: SynthesisService) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(service.progress)
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)

            // Show scope summary while generating
            VStack(spacing: 4) {
                Text(scopeTitle)
                    .font(.groveBodySecondary)
                    .foregroundStyle(Color.textPrimary)
                Text("\(items.count) items")
                    .font(.groveMeta)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.top, 8)

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
                .foregroundStyle(Color.textSecondary)
            Text("Synthesis Failed")
                .font(.groveBody)
                .fontWeight(.medium)
                .foregroundStyle(Color.textPrimary)
            Text(error)
                .font(.groveBodySecondary)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Try Again") {
                startGeneration()
            }
            .buttonStyle(.bordered)
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
                TextField("Synthesis title", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.groveTitleLarge)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button {
                    isEditing.toggle()
                } label: {
                    Text(isEditing ? "Preview" : "Edit")
                        .font(.groveBadge)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentBadge)
                .clipShape(Capsule())
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            ScrollView {
                if isEditing {
                    TextEditor(text: $draftContent)
                        .font(.custom("IBMPlexMono", size: 12))
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
                .tint(Color.textPrimary)
                .keyboardShortcut(.defaultAction)
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
                result = generated
                draftContent = generated.markdownContent
                hasGenerated = true
            }
        }
    }

    private func saveNote() {
        guard let result, let service = synthesisService else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Synthesis: \(scopeTitle)"
            : draftTitle

        // If user edited the content, use the edited version and mark as edited
        var finalResult = result
        if draftContent != result.markdownContent {
            finalResult = SynthesisResult(
                markdownContent: draftContent,
                sourceItemIDs: result.sourceItemIDs,
                isLLMGenerated: result.isLLMGenerated
            )
        }

        let item = service.createSynthesisItem(from: finalResult, title: title, inBoard: board)

        // If user edited content before saving, mark as edited
        if draftContent != result.markdownContent {
            item.metadata["isAIEdited"] = "true"
        }

        onCreated(item)
        dismiss()
    }
}
