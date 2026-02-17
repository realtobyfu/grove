import SwiftUI
import SwiftData

/// A non-blocking nudge bar displayed at the top of the content area.
/// Shows one nudge at a time with action and dismiss buttons.
struct NudgeBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Nudge.createdAt, order: .reverse) private var allNudges: [Nudge]

    var onOpenItem: ((Item) -> Void)?
    var onTriageInbox: (() -> Void)?

    private var currentNudge: Nudge? {
        allNudges.first { $0.status == .pending || $0.status == .shown }
    }

    var body: some View {
        if let nudge = currentNudge {
            HStack(spacing: 12) {
                Image(systemName: nudge.type.iconName)
                    .font(.subheadline)
                    .foregroundStyle(nudge.type.accentColor)

                Text(nudge.message)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Button(nudge.type.actionLabel) {
                    actOnNudge(nudge)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    dismissNudge(nudge)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                if nudge.status == .pending {
                    nudge.status = .shown
                    try? modelContext.save()
                }
            }
        }
    }

    private func actOnNudge(_ nudge: Nudge) {
        withAnimation(.easeOut(duration: 0.25)) {
            nudge.status = .actedOn
            NudgeSettings.recordAction(type: nudge.type, actedOn: true)
            try? modelContext.save()
        }

        switch nudge.type {
        case .resurface:
            if let item = nudge.targetItem {
                onOpenItem?(item)
            }
        case .staleInbox:
            onTriageInbox?()
        case .connectionPrompt, .streak:
            break
        }
    }

    private func dismissNudge(_ nudge: Nudge) {
        withAnimation(.easeOut(duration: 0.25)) {
            nudge.status = .dismissed
            NudgeSettings.recordAction(type: nudge.type, actedOn: false)
            try? modelContext.save()
        }
    }
}

// MARK: - NudgeType UI Helpers

extension NudgeType {
    var iconName: String {
        switch self {
        case .resurface: "arrow.clockwise.circle"
        case .staleInbox: "tray.full"
        case .connectionPrompt: "link.circle"
        case .streak: "flame"
        }
    }

    var actionLabel: String {
        switch self {
        case .resurface: "Open"
        case .staleInbox: "Triage"
        case .connectionPrompt: "Connect"
        case .streak: "View"
        }
    }

    var accentColor: Color {
        switch self {
        case .resurface: .blue
        case .staleInbox: .orange
        case .connectionPrompt: .purple
        case .streak: .red
        }
    }
}
