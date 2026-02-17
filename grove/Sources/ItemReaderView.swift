import SwiftUI
import SwiftData

struct ItemReaderView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @State private var isAddingAnnotation = false
    @State private var newAnnotationText = ""
    @State private var editingAnnotationID: UUID?
    @State private var editAnnotationText = ""
    @State private var isEditingContent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                itemHeader

                Divider()
                    .padding(.horizontal)

                // Content
                itemContent
                    .padding()

                Divider()
                    .padding(.horizontal)

                // Annotations section
                annotationsSection
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var itemHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.type.iconName)
                    .foregroundStyle(.secondary)
                Text(item.type.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if item.type == .note {
                    Button {
                        isEditingContent.toggle()
                    } label: {
                        Label(isEditingContent ? "Done" : "Edit", systemImage: isEditingContent ? "checkmark" : "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Text(item.title)
                .font(.title)
                .fontWeight(.bold)
                .textSelection(.enabled)

            if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
                Link(destination: URL(string: sourceURL) ?? URL(string: "about:blank")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption)
                        Text(sourceURL)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 16) {
                Label(item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Label("\(item.annotations.count) annotations", systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var itemContent: some View {
        if isEditingContent && item.type == .note {
            TextEditor(text: Binding(
                get: { item.content ?? "" },
                set: {
                    item.content = $0.isEmpty ? nil : $0
                    item.updatedAt = .now
                }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 200)
            .padding(8)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let content = item.content, !content.isEmpty {
            MarkdownTextView(markdown: content)
                .textSelection(.enabled)
        } else {
            Text("No content available.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    // MARK: - Annotations

    private var sortedAnnotations: [Annotation] {
        item.annotations.sorted { $0.createdAt < $1.createdAt }
    }

    private var annotationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Annotations")
                    .font(.headline)

                Text("\(item.annotations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())

                Spacer()

                Button {
                    isAddingAnnotation = true
                    newAnnotationText = ""
                } label: {
                    Label("Add Annotation", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // New annotation input
            if isAddingAnnotation {
                newAnnotationEditor
            }

            // Annotation list
            if sortedAnnotations.isEmpty && !isAddingAnnotation {
                Text("No annotations yet. Add one to capture your thoughts.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(sortedAnnotations) { annotation in
                    annotationCard(annotation)
                }
            }
        }
    }

    private var newAnnotationEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Annotation")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $newAnnotationText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(8)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.blue.opacity(0.5), lineWidth: 1)
                )

            Text("Supports markdown: **bold**, *italic*, `code`, # headings, [links](url)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack {
                Button("Cancel") {
                    isAddingAnnotation = false
                    newAnnotationText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save") {
                    saveNewAnnotation()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newAnnotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
        .background(.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func annotationCard(_ annotation: Annotation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with date and actions
            HStack {
                Label(annotation.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Menu {
                    Button {
                        editingAnnotationID = annotation.id
                        editAnnotationText = annotation.content
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleteAnnotation(annotation)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }

            // Content or edit mode
            if editingAnnotationID == annotation.id {
                editAnnotationEditor(annotation)
            } else {
                MarkdownTextView(markdown: annotation.content)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func editAnnotationEditor(_ annotation: Annotation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $editAnnotationText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60)
                .padding(8)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.blue.opacity(0.5), lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    editingAnnotationID = nil
                    editAnnotationText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save") {
                    saveEditedAnnotation(annotation)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(editAnnotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func saveNewAnnotation() {
        let content = newAnnotationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let annotation = Annotation(item: item, content: content)
        modelContext.insert(annotation)
        item.annotations.append(annotation)
        item.updatedAt = .now
        try? modelContext.save()

        newAnnotationText = ""
        isAddingAnnotation = false
    }

    private func saveEditedAnnotation(_ annotation: Annotation) {
        let content = editAnnotationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        annotation.content = content
        item.updatedAt = .now
        try? modelContext.save()

        editingAnnotationID = nil
        editAnnotationText = ""
    }

    private func deleteAnnotation(_ annotation: Annotation) {
        item.annotations.removeAll { $0.id == annotation.id }
        modelContext.delete(annotation)
        item.updatedAt = .now
        try? modelContext.save()
    }
}

// MARK: - Markdown Text View

struct MarkdownTextView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case codeBlock(language: String?, code: String)
        case paragraph(text: String)
    }

    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Code block
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n")
                ))
                i += 1
                continue
            }

            // Heading
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if level >= 1 && level <= 6 && !text.isEmpty {
                    blocks.append(.heading(level: level, text: text))
                    i += 1
                    continue
                }
            }

            // Empty line — skip
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Paragraph: collect consecutive non-empty, non-special lines
            var paragraphLines: [String] = [line]
            i += 1
            while i < lines.count {
                let nextLine = lines[i]
                if nextLine.trimmingCharacters(in: .whitespaces).isEmpty
                    || nextLine.hasPrefix("#")
                    || nextLine.hasPrefix("```") {
                    break
                }
                paragraphLines.append(nextLine)
                i += 1
            }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: "\n")))
        }

        return blocks
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .codeBlock(_, let code):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.windowBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))

        case .paragraph(let text):
            if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed)
                    .font(.body)
                    .tint(.blue)
            } else {
                Text(text)
                    .font(.body)
            }
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)

        switch level {
        case 1:
            Text(attributed)
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 8)
        case 2:
            Text(attributed)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 6)
        case 3:
            Text(attributed)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.top, 4)
        default:
            Text(attributed)
                .font(.headline)
                .padding(.top, 2)
        }
    }
}
