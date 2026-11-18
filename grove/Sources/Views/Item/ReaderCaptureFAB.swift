import SwiftUI

/// What the reader's capture button can offer for the page on screen.
enum ReaderCaptureState: String, Equatable {
    /// Not in the library yet.
    case unsaved
    /// In the library, but not on any board.
    case unfiled
    /// In the library and filed. The FAB only shows this as a transient
    /// confirmation right after filing, then disappears — a filed page
    /// carries no button, and board changes live in the metadata panel.
    case filed

    var glyph: String {
        switch self {
        case .unsaved, .unfiled: "plus"
        case .filed: "checkmark"
        }
    }

    var label: String {
        switch self {
        case .unsaved: "Save and add to board"
        case .unfiled: "Add to board"
        case .filed: "Filed"
        }
    }
}

/// The single capture affordance in the reader: one round ink button,
/// bottom-trailing of the content, whose meaning follows the page on screen.
///
/// Replaces the toolbar's "+" boards menu and its conditional save button —
/// two affordances that answered the same question in different places.
///
/// On a Mac, resting the pointer on it for a moment shows what it will do in
/// a quiet label beside it. The label is a hint, not part of the button: it
/// takes no clicks, and the button itself never changes shape. A press sinks
/// the button slightly. On iOS there is no hover, so there is no label.
struct ReaderCaptureFAB: View {
    let state: ReaderCaptureState
    /// Identifies the page on screen. Changing it replays the entrance
    /// animation, so arriving somewhere new is what the motion means.
    let pageKey: String
    var action: () -> Void

    @State private var isHovering = false
    @State private var showsLabel = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(iOS)
    private static let diameter: CGFloat = 44
    private static let glyphSize: CGFloat = 17
    #else
    private static let diameter: CGFloat = 40
    private static let glyphSize: CGFloat = 15
    #endif

    /// How long the pointer has to rest before the label shows. Long enough
    /// that crossing the button on the way to the page does not flash it.
    private static let labelDelay: Duration = .milliseconds(220)

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if showsLabel {
                Text(state.label)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.bgCard))
                    .overlay(Capsule().stroke(Color.borderPrimary, lineWidth: 1))
                    // A hint beside the button, not a second target: moving
                    // onto it leaves the button, and the hint goes with it.
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .offset(x: Spacing.sm))
                    )
            }

            Button(action: action) {
                Image(systemName: state.glyph)
                    .font(.system(size: Self.glyphSize, weight: .medium))
                    .foregroundStyle(Color.textInverse)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.diameter, height: Self.diameter)
                    .background(Circle().fill(Color.textPrimary))
                    .contentShape(Circle())
            }
            .buttonStyle(CaptureFABButtonStyle(isHovering: isHovering, reduceMotion: reduceMotion))
            .accessibilityLabel(state.label)
            .onHover { hovering in
                isHovering = hovering
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: Self.labelDelay)
                        guard !Task.isCancelled else { return }
                        showsLabel = true
                    }
                } else {
                    showsLabel = false
                }
            }
        }
        .opacity(opacity)
        // During the entrance delay the button is invisible; it must not be
        // an invisible tap target either.
        .allowsHitTesting(opacity > 0)
        .scaleEffect(scale, anchor: .bottomTrailing)
        .animation(.easeOut(duration: 0.16), value: showsLabel)
        .onDisappear {
            hoverTask?.cancel()
        }
        .task(id: "\(pageKey)|\(state.rawValue)") {
            // Landing on an unsaved page is the only moment worth animating —
            // a saved page should already be settled when the reader looks.
            guard state == .unsaved else {
                scale = 1
                opacity = 1
                return
            }
            // Reduce Motion: fade in place, no scale-up.
            scale = reduceMotion ? 1 : 0.6
            opacity = 0
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                scale = 1
                opacity = 1
            }
        }
    }
}

/// Hover and press for the capture button. It floats over the page, so it is
/// the one control that keeps a shadow; the shadow is what responds. Hovering
/// lifts it a little, pressing sets it back down and sinks the button.
private struct CaptureFABButtonStyle: ButtonStyle {
    let isHovering: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let lifted = isHovering && !pressed
        return configuration.label
            .opacity(pressed ? 0.88 : 1)
            .scaleEffect(pressed && !reduceMotion ? 0.95 : 1, anchor: .center)
            .shadow(
                color: .black.opacity(lifted ? 0.18 : 0.12),
                radius: lifted ? 10 : (pressed ? 3 : 6),
                y: lifted ? 4 : (pressed ? 1 : 2)
            )
            .animation(.easeOut(duration: pressed ? 0.06 : 0.16), value: pressed)
            .animation(.easeOut(duration: 0.16), value: isHovering)
    }
}
