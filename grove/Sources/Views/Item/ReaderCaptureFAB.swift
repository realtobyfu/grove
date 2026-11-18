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
/// On a Mac, resting the pointer on it for a moment opens it leftward into an
/// ink capsule that names what it will do; the whole capsule is the button,
/// so the label can be clicked too. It closes as soon as the pointer leaves.
/// A press sinks it slightly. On iOS there is no hover, so it stays a circle.
struct ReaderCaptureFAB: View {
    let state: ReaderCaptureState
    /// Identifies the page on screen. Changing it replays the entrance
    /// animation, so arriving somewhere new is what the motion means.
    let pageKey: String
    var action: () -> Void

    @State private var isHovering = false
    @State private var isExpanded = false
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

    /// How long the pointer has to rest before the label opens. Long enough
    /// that crossing the button on the way to the page does not flash it.
    private static let expandDelay: Duration = .milliseconds(220)

    private var expandAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.86)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if isExpanded {
                    Text(state.label)
                        .font(.groveMeta)
                        .foregroundStyle(Color.textInverse)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, Spacing.lg)
                        .transition(.opacity)
                }

                Image(systemName: state.glyph)
                    .font(.system(size: Self.glyphSize, weight: .medium))
                    .foregroundStyle(Color.textInverse)
                    .frame(width: Self.diameter, height: Self.diameter)
                    // The glyph turns as the label opens: a quarter turn of
                    // "+" reads as the same mark, and gives the change a hinge.
                    .rotationEffect(.degrees(isExpanded && state != .filed && !reduceMotion ? 90 : 0))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(height: Self.diameter)
            .background(Capsule().fill(Color.textPrimary))
            .contentShape(Capsule())
        }
        .buttonStyle(CaptureFABButtonStyle(isHovering: isHovering, reduceMotion: reduceMotion))
        .accessibilityLabel(state.label)
        .opacity(opacity)
        // During the entrance delay the button is invisible; it must not be
        // an invisible tap target either.
        .allowsHitTesting(opacity > 0)
        .scaleEffect(scale, anchor: .bottomTrailing)
        .animation(expandAnimation, value: isExpanded)
        .animation(expandAnimation, value: state)
        .onHover { hovering in
            isHovering = hovering
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: Self.expandDelay)
                    guard !Task.isCancelled else { return }
                    isExpanded = true
                }
            } else {
                isExpanded = false
            }
        }
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
            .scaleEffect(pressed && !reduceMotion ? 0.95 : 1, anchor: .bottomTrailing)
            .shadow(
                color: .black.opacity(lifted ? 0.18 : 0.12),
                radius: lifted ? 10 : (pressed ? 3 : 6),
                y: lifted ? 4 : (pressed ? 1 : 2)
            )
            .animation(.easeOut(duration: pressed ? 0.06 : 0.16), value: pressed)
            .animation(.easeOut(duration: 0.16), value: isHovering)
    }
}
