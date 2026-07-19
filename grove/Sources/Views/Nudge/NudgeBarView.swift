import SwiftUI
import SwiftData

/// A non-blocking nudge bar displayed at the top of the content area.
/// Shows one nudge at a time with action and dismiss buttons.
/// Styled per DESIGN.md: card background, border.primary, border-radius 6px,
/// body.secondary text with inline emphasis, pill action button, muted dismiss.
struct NudgeBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Nudge.createdAt, order: .reverse) private var allNudges: [Nudge]

    var onOpenItem: ((Item) -> Void)?
    var onTriageInbox: (() -> Void)?
    var resurfacingService: ResurfacingService?

    @State private var showReflectionPrompt = false
    @State private var reflectionText = ""

    private var currentNudge: Nudge? {
        allNudges.first { $0.status == .pending || $0.status == .shown }
    }

    var body: some View {
        if let nudge = currentNudge {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: nudge.type.iconName)
                        .font(.groveBody)
                        .foregroundStyle(Color.textSecondary)

                    Text(nudge.displayMessage)
                        .font(.groveBodySecondary)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)

                    Spacer()

                    // Reflection prompt toggle for resurface nudges
                    if nudge.type == .resurface, nudge.targetItem != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showReflectionPrompt.toggle()
                            }
                        } label: {
                            Image(systemName: "text.bubble")
                                .font(.groveMeta)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.textSecondary)
                        .help("Add a quick reflection")
                    }

                    // Action button — pill style per DESIGN.md
                    Button {
                        actOnNudge(nudge)
                    } label: {
                        Text(nudge.type.actionLabel)
                            .font(.groveBadge)
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentBadge)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // Dismiss — muted "✕"
                    Button {
                        dismissNudge(nudge)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textMuted)
                }

                // Reflection prompt area
                if showReflectionPrompt, nudge.type == .resurface {
                    HStack(spacing: 8) {
                        TextField("What was the key insight from this?", text: $reflectionText)
                            .textFieldStyle(.roundedBorder)
                            .font(.groveBodySecondary)
                            .onSubmit {
                                submitReflection(for: nudge)
                            }

                        Button("Save") {
                            submitReflection(for: nudge)
                        }
                        .font(.groveBadge)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Color.textPrimary)
                        .disabled(reflectionText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                if nudge.status == .pending {
                    nudge.status = .shown
                    try? modelContext.save()
                }
                NudgeNotificationService.shared.cancel(for: nudge.id)
            }
            .onChange(of: currentNudge?.id) {
                showReflectionPrompt = false
                reflectionText = ""
            }
        }
    }

    private func submitReflection(for nudge: Nudge) {
        let text = reflectionText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let item = nudge.targetItem else { return }

        let nextPosition = (item.reflections.map(\.position).max() ?? -1) + 1
        let block = ReflectionBlock(item: item, blockType: .keyInsight, content: text, position: nextPosition)
        modelContext.insert(block)
        item.reflections.append(block)
        WikiLinkSync.sync(item: item, content: text, modelContext: modelContext)

        resurfacingService?.recordEngagement(for: item)

        withAnimation(.easeOut(duration: 0.15)) {
            nudge.status = .actedOn
            NudgeSettings.recordAction(type: nudge.type, actedOn: true)
            try? modelContext.save()
        }
        NudgeNotificationService.shared.cancel(for: nudge.id)

        reflectionText = ""
        showReflectionPrompt = false
    }

    private func actOnNudge(_ nudge: Nudge) {
        if nudge.type == .resurface, let item = nudge.targetItem {
            resurfacingService?.recordEngagement(for: item)
        }

        withAnimation(.easeOut(duration: 0.15)) {
            nudge.status = .actedOn
            NudgeSettings.recordAction(type: nudge.type, actedOn: true)
            try? modelContext.save()
        }
        NudgeNotificationService.shared.cancel(for: nudge.id)

        switch nudge.type {
        case .staleInbox:
            onTriageInbox?()
        default:
            // Resurface plus legacy types retained only for persisted records.
            if let item = nudge.targetItem {
                onOpenItem?(item)
            }
        }
    }

    private func dismissNudge(_ nudge: Nudge) {
        withAnimation(.easeOut(duration: 0.15)) {
            nudge.status = .dismissed
            NudgeSettings.recordAction(type: nudge.type, actedOn: false)
            try? modelContext.save()
        }
        NudgeNotificationService.shared.cancel(for: nudge.id)
    }
}

// MARK: - Nudge Display Helpers

extension Nudge {
    /// The user-facing message. For dialectical check-ins, extracts the portion before `|||`.
    var displayMessage: String {
        if type == .dialecticalCheckIn, let range = message.range(of: "|||") {
            return String(message[message.startIndex..<range.lowerBound])
        }
        return message
    }

}

// MARK: - NudgeType UI Helpers

extension NudgeType {
    var iconName: String {
        switch self {
        case .resurface: "arrow.clockwise.circle"
        case .staleInbox: "tray.full"
        default: "bell"
        }
    }

    var actionLabel: String {
        switch self {
        case .staleInbox: "Triage"
        default: "Open"
        }
    }
}
