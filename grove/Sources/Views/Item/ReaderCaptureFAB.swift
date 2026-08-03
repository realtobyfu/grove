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

/// The single capture affordance in the reader: one ink disc, bottom-trailing
/// of the content, whose meaning follows the page currently on screen.
///
/// Replaces the toolbar's "+" boards menu and its conditional save button —
/// two affordances that answered the same question in different places.
struct ReaderCaptureFAB: View {
    let state: ReaderCaptureState
    /// Identifies the page on screen. Changing it replays the entrance
    /// animation, so arriving somewhere new is what the motion means.
    let pageKey: String
    var action: () -> Void

    @State private var isHovering = false
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1

    #if os(iOS)
    private static let diameter: CGFloat = 44
    private static let glyphSize: CGFloat = 17
    #else
    private static let diameter: CGFloat = 38
    private static let glyphSize: CGFloat = 15
    #endif

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if isHovering {
                Text(state.label)
                    .font(.groveMeta)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 6)
                    .background(Color.bgCard)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.borderPrimary, lineWidth: 1))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button(action: action) {
                Image(systemName: state.glyph)
                    .font(.system(size: Self.glyphSize, weight: .medium))
                    .foregroundStyle(Color.textInverse)
                    .frame(width: Self.diameter, height: Self.diameter)
                    .background(Color.textPrimary)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.label)
        }
        .opacity(opacity)
        // During the entrance delay the disc is invisible; it must not be
        // an invisible tap target either.
        .allowsHitTesting(opacity > 0)
        .scaleEffect(scale, anchor: .bottomTrailing)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .task(id: "\(pageKey)|\(state.rawValue)") {
            // Landing on an unsaved page is the only moment worth animating —
            // a saved page should already be settled when the reader looks.
            guard state == .unsaved else {
                scale = 1
                opacity = 1
                return
            }
            scale = 0.6
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
