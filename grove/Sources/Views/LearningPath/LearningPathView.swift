import SwiftUI
import SwiftData

/// Sheet for generating a learning path from board items.
struct LearningPathSheet: View {
    let items: [Item]
    let topic: String
    let board: Board?
    let onCreated: (LearningPath) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var service: LearningPathService?
    @State private var generatedPath: LearningPath?

    // MARK: - DESIGN.md Color Tokens

    private var cardBackground: Color {
        Color(hex: colorScheme == .dark ? "1A1A1A" : "FFFFFF")
    }
    private var borderColor: Color {
        Color(hex: colorScheme == .dark ? "222222" : "EBEBEB")
    }
    private var textPrimary: Color {
        Color(hex: colorScheme == .dark ? "E8E8E8" : "1A1A1A")
    }
    private var textSecondary: Color {
        Color(hex: colorScheme == .dark ? "888888" : "777777")
    }
    private var textMuted: Color {
        Color(hex: colorScheme == .dark ? "444444" : "BBBBBB")
    }
    private var badgeBackground: Color {
        Color(hex: colorScheme == .dark ? "2A2A2A" : "E8E8E8")
    }
    private var backgroundPrimary: Color {
        Color(hex: colorScheme == .dark ? "111111" : "FAFAFA")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let service, service.isGenerating {
                generatingView(service: service)
            } else if let path = generatedPath {
                pathPreview(path: path)
            } else {
                scopeOverview
            }

            Divider()
            footer
        }
        .frame(width: 600, height: 550)
        .background(backgroundPrimary)
        .onAppear {
            service = LearningPathService()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("LEARNING PATH")
                .font(.custom("IBMPlexMono", size: 10))
                .fontWeight(.medium)
                .tracking(1.2)
                .foregroundStyle(textMuted)

            Spacer()

            Text("\(items.count) items")
                .font(.custom("IBMPlexMono", size: 10))
                .foregroundStyle(textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(badgeBackground)
                .clipShape(Capsule())
        }
        .padding()
    }

    // MARK: - Scope Overview

    private var scopeOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TOPIC")
                        .font(.custom("IBMPlexMono", size: 10))
                        .fontWeight(.medium)
                        .tracking(1.2)
                        .foregroundStyle(textMuted)

                    Text(topic)
                        .font(.custom("IBMPlexSans-Regular", size: 13))
                        .fontWeight(.medium)
                        .foregroundStyle(textPrimary)
                }

                Text("ITEMS TO SEQUENCE")
                    .font(.custom("IBMPlexMono", size: 10))
                    .fontWeight(.medium)
                    .tracking(1.2)
                    .foregroundStyle(textMuted)

                ForEach(items.prefix(20)) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.type.iconName)
                            .font(.groveBadge)
                            .foregroundStyle(textSecondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.custom("IBMPlexSans-Regular", size: 12))
                                .foregroundStyle(textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                if !item.tags.isEmpty {
                                    Text(item.tags.prefix(3).map(\.name).joined(separator: ", "))
                                        .font(.custom("IBMPlexMono", size: 10))
                                        .foregroundStyle(textMuted)
                                }
                            }
                        }
                        Spacer()
                        GrowthStageIndicator(stage: item.growthStage)
                    }
                }

                if items.count > 20 {
                    Text("...and \(items.count - 20) more")
                        .font(.custom("IBMPlexSans-Regular", size: 11))
                        .foregroundStyle(textMuted)
                }

                if LLMServiceConfig.isConfigured {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text("AI will sequence items for optimal learning progression")
                            .font(.custom("IBMPlexSans-Regular", size: 11))
                    }
                    .foregroundStyle(textSecondary)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                        Text("Local ordering by depth score — configure AI in Settings for smarter sequencing")
                            .font(.custom("IBMPlexSans-Regular", size: 11))
                    }
                    .foregroundStyle(textMuted)
                }
            }
            .padding()
        }
    }

    // MARK: - Generating

    private func generatingView(service: LearningPathService) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(service.progress)
                .font(.custom("IBMPlexSans-Regular", size: 12))
                .foregroundStyle(textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Path Preview

    private func pathPreview(path: LearningPath) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let sortedSteps = path.steps.sorted { $0.position < $1.position }
                ForEach(Array(sortedSteps.enumerated()), id: \.element.id) { index, step in
                    pathStepRow(step: step, index: index, isLast: index == sortedSteps.count - 1)
                }
            }
            .padding()
        }
    }

    private func pathStepRow(step: LearningPathStep, index: Int, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number / timeline
            VStack(spacing: 0) {
                if step.isSynthesisStep {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(textSecondary)
                        .frame(width: 24, height: 24)
                        .background(badgeBackground)
                        .clipShape(Circle())
                } else {
                    Text("\(index + 1)")
                        .font(.custom("IBMPlexMono", size: 11))
                        .fontWeight(.semibold)
                        .foregroundStyle(textSecondary)
                        .frame(width: 24, height: 24)
                        .background(badgeBackground)
                        .clipShape(Circle())
                }

                if !isLast {
                    Rectangle()
                        .fill(borderColor)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }

            // Step content
            VStack(alignment: .leading, spacing: 4) {
                if step.isSynthesisStep {
                    Text("Write a Synthesis Note")
                        .font(.custom("IBMPlexSans-Regular", size: 13))
                        .fontWeight(.medium)
                        .foregroundStyle(textPrimary)
                } else if let item = step.item {
                    HStack(spacing: 6) {
                        Image(systemName: item.type.iconName)
                            .font(.groveBadge)
                            .foregroundStyle(textSecondary)
                        Text(item.title)
                            .font(.custom("IBMPlexSans-Regular", size: 13))
                            .fontWeight(.medium)
                            .foregroundStyle(textPrimary)
                            .lineLimit(2)
                    }
                } else {
                    Text("Unknown item")
                        .font(.custom("IBMPlexSans-Regular", size: 13))
                        .foregroundStyle(textMuted)
                        .italic()
                }

                Text(step.reason)
                    .font(.custom("IBMPlexSans-Regular", size: 11))
                    .foregroundStyle(textSecondary)
                    .lineLimit(3)

                if let item = step.item {
                    HStack(spacing: 8) {
                        Image(systemName: step.progress.systemImage)
                            .font(.system(size: 10))
                            .foregroundStyle(step.progress == .reflected ? textPrimary : textMuted)
                        Text(step.progress.displayName)
                            .font(.custom("IBMPlexMono", size: 10))
                            .foregroundStyle(step.progress == .reflected ? textPrimary : textMuted)

                        if !item.tags.isEmpty {
                            Text(item.tags.prefix(2).map(\.name).joined(separator: ", "))
                                .font(.custom("IBMPlexMono", size: 10))
                                .foregroundStyle(textMuted)
                        }
                    }
                }
            }
            .padding(.bottom, 12)

            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .foregroundStyle(textSecondary)

            Spacer()

            if generatedPath != nil {
                Button("Regenerate") {
                    startGeneration()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Save Path") {
                    savePath()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(Color(hex: "1A1A1A"))
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Generate Path") {
                    startGeneration()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(Color(hex: "1A1A1A"))
                .keyboardShortcut(.defaultAction)
                .disabled(service?.isGenerating == true || items.count < 2)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func startGeneration() {
        guard let service else { return }

        // Delete previous path if regenerating
        if let old = generatedPath {
            modelContext.delete(old)
            generatedPath = nil
        }

        Task {
            generatedPath = await service.generatePath(
                items: items,
                topic: topic,
                board: board,
                in: modelContext
            )
        }
    }

    private func savePath() {
        guard let path = generatedPath else { return }
        try? modelContext.save()
        onCreated(path)
        dismiss()
    }
}

// MARK: - Learning Path Detail View

/// Full detail view for a saved learning path, shown when navigated to.
struct LearningPathDetailView: View {
    let learningPath: LearningPath
    @Binding var openedItem: Item?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSynthesisSheet = false

    // MARK: - DESIGN.md Color Tokens

    private var cardBackground: Color {
        Color(hex: colorScheme == .dark ? "1A1A1A" : "FFFFFF")
    }
    private var borderColor: Color {
        Color(hex: colorScheme == .dark ? "222222" : "EBEBEB")
    }
    private var textPrimary: Color {
        Color(hex: colorScheme == .dark ? "E8E8E8" : "1A1A1A")
    }
    private var textSecondary: Color {
        Color(hex: colorScheme == .dark ? "888888" : "777777")
    }
    private var textMuted: Color {
        Color(hex: colorScheme == .dark ? "444444" : "BBBBBB")
    }
    private var badgeBackground: Color {
        Color(hex: colorScheme == .dark ? "2A2A2A" : "E8E8E8")
    }
    private var backgroundPrimary: Color {
        Color(hex: colorScheme == .dark ? "111111" : "FAFAFA")
    }
    private var accentSelection: Color {
        Color(hex: colorScheme == .dark ? "E8E8E8" : "1A1A1A")
    }

    /// Items associated with the path steps, for synthesis.
    private var pathItems: [Item] {
        learningPath.steps
            .sorted { $0.position < $1.position }
            .compactMap(\.item)
    }

    /// Progress summary.
    private var completedCount: Int {
        learningPath.steps.filter { $0.progress == .reflected && !$0.isSynthesisStep }.count
    }
    private var totalSteps: Int {
        learningPath.steps.filter { !$0.isSynthesisStep }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("LEARNING PATH")
                        .font(.custom("IBMPlexMono", size: 10))
                        .fontWeight(.medium)
                        .tracking(1.2)
                        .foregroundStyle(textMuted)

                    Text(learningPath.title)
                        .font(.custom("Newsreader", size: 28).weight(.medium))
                        .tracking(-0.5)
                        .foregroundStyle(textPrimary)

                    HStack(spacing: 12) {
                        Text("\(completedCount)/\(totalSteps) completed")
                            .font(.custom("IBMPlexMono", size: 11))
                            .foregroundStyle(textSecondary)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: colorScheme == .dark ? "222222" : "EBEBEB"))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(accentSelection)
                                    .frame(width: totalSteps > 0 ? geo.size.width * CGFloat(completedCount) / CGFloat(totalSteps) : 0, height: 4)
                            }
                        }
                        .frame(height: 4)
                        .frame(maxWidth: 120)

                        Text(learningPath.createdAt.formatted(.dateTime.month().day()))
                            .font(.custom("IBMPlexMono", size: 10))
                            .foregroundStyle(textMuted)
                    }
                }

                Divider()

                // Steps
                let sortedSteps = learningPath.steps.sorted { $0.position < $1.position }
                ForEach(Array(sortedSteps.enumerated()), id: \.element.id) { index, step in
                    detailStepRow(step: step, index: index, isLast: index == sortedSteps.count - 1)
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundPrimary)
        .sheet(isPresented: $showSynthesisSheet) {
            SynthesisSheet(
                items: pathItems,
                scopeTitle: learningPath.topic,
                board: learningPath.board,
                onCreated: { item in
                    openedItem = item
                }
            )
        }
    }

    private func detailStepRow(step: LearningPathStep, index: Int, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline
            VStack(spacing: 0) {
                if step.isSynthesisStep {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(textSecondary)
                        .frame(width: 32, height: 32)
                        .background(badgeBackground)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(step.progress == .reflected ? accentSelection : badgeBackground)
                            .frame(width: 32, height: 32)
                        Text("\(index + 1)")
                            .font(.custom("IBMPlexMono", size: 13))
                            .fontWeight(.semibold)
                            .foregroundStyle(step.progress == .reflected
                                ? (colorScheme == .dark ? Color(hex: "111111") : Color.white)
                                : textSecondary)
                    }
                }

                if !isLast {
                    Rectangle()
                        .fill(borderColor)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }

            // Content card
            VStack(alignment: .leading, spacing: 8) {
                if step.isSynthesisStep {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Write a Synthesis Note")
                            .font(.custom("IBMPlexSans-Regular", size: 14))
                            .fontWeight(.medium)
                            .foregroundStyle(textPrimary)

                        Text(step.reason)
                            .font(.custom("IBMPlexSans-Regular", size: 12))
                            .foregroundStyle(textSecondary)

                        Button {
                            showSynthesisSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("Synthesize")
                                    .font(.custom("IBMPlexMono", size: 11))
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(badgeBackground)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                } else if let item = step.item {
                    Button {
                        openedItem = item
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: item.type.iconName)
                                    .font(.groveBadge)
                                    .foregroundStyle(textSecondary)
                                Text(item.title)
                                    .font(.custom("IBMPlexSans-Regular", size: 14))
                                    .fontWeight(.medium)
                                    .foregroundStyle(textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }

                            Text(step.reason)
                                .font(.custom("IBMPlexSans-Regular", size: 12))
                                .foregroundStyle(textSecondary)
                                .lineLimit(3)

                            HStack(spacing: 10) {
                                HStack(spacing: 4) {
                                    Image(systemName: step.progress.systemImage)
                                        .font(.system(size: 11))
                                    Text(step.progress.displayName)
                                        .font(.custom("IBMPlexMono", size: 10))
                                }
                                .foregroundStyle(step.progress == .reflected ? textPrimary : textMuted)

                                GrowthStageIndicator(stage: item.growthStage)

                                if !item.tags.isEmpty {
                                    Text(item.tags.prefix(3).map(\.name).joined(separator: ", "))
                                        .font(.custom("IBMPlexMono", size: 10))
                                        .foregroundStyle(textMuted)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Item unavailable")
                        .font(.custom("IBMPlexSans-Regular", size: 13))
                        .foregroundStyle(textMuted)
                        .italic()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if step.progress == .reflected && !step.isSynthesisStep {
                    Rectangle()
                        .fill(accentSelection)
                        .frame(width: 2)
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                }
            }
        }
        .padding(.bottom, 4)
    }
}
