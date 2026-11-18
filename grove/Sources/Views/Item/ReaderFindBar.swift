import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Reader Find Bar

/// The reader's find-in-article bar: field, count, previous / next, close.
///
/// It sits inside the reading panel, directly under the panel's own strip —
/// never in the window toolbar, which is hidden when a reading surface is in
/// full screen. Typing searches after a short pause; Return steps forward,
/// Shift-Return back, Esc closes. The surface underneath does the searching;
/// this view only talks to the `ReaderFindSession`.
struct ReaderFindBar: View {
    @Bindable var find: ReaderFindSession
    var placeholder: String = "Find in article"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFieldFocused: Bool

    /// How long typing has to pause before the page is searched.
    private static let typingPause: Duration = .milliseconds(160)

    #if os(iOS)
    private static let buttonSize: CGFloat = LayoutDimensions.minTouchTarget
    #else
    private static let buttonSize: CGFloat = 22
    #endif

    /// Showing and hiding the bar: a quick fade, or nothing under Reduce Motion.
    static func revealAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    static func revealTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xs) {
                field
                    .padding(.trailing, Spacing.xs)

                stepButton(
                    systemImage: "chevron.up",
                    label: "Previous match",
                    help: "Previous match (\u{21E7}\u{21A9} or \u{21E7}\u{2318}G)"
                ) {
                    find.findPrevious()
                }

                stepButton(
                    systemImage: "chevron.down",
                    label: "Next match",
                    help: "Next match (\u{21A9} or \u{2318}G)"
                ) {
                    find.findNext()
                }

                Spacer(minLength: 0)

                closeButton
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xsm)
            .background(Color.bgCard)

            Divider()
        }
        .onAppear { focusField() }
        .onChange(of: find.focusToken) { focusField() }
        // Search as you type, lightly debounced: each keystroke restarts the
        // wait, and only the text that survives the pause reaches the page.
        .task(id: find.query) {
            try? await Task.sleep(for: Self.typingPause)
            guard !Task.isCancelled else { return }
            find.commitQuery()
        }
    }

    // MARK: - Field

    private var field: some View {
        HStack(spacing: Spacing.xsm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)

            TextField(
                "",
                text: $find.query,
                prompt: Text(placeholder)
                    .font(.groveBodySmall)
                    .foregroundStyle(Color.textMuted)
            )
            .textFieldStyle(.plain)
            .font(.groveBodySmall)
            .foregroundStyle(Color.textPrimary)
            .focused($isFieldFocused)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
            // Return arrives through onSubmit, which leaves input methods
            // their own use of the key. Shift-Return is claimed here first in
            // case the field would not submit it; `submit` reads the modifier
            // as well, so whichever path delivers it, it steps back once.
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers.contains(.shift) else { return .ignored }
                find.findPrevious()
                return .handled
            }
            .onSubmit { submit() }
            #if os(macOS)
            .onExitCommand { close() }
            #endif
            .accessibilityLabel(placeholder)

            if !find.statusLabel.isEmpty {
                Text(find.statusLabel)
                    .font(.groveMeta)
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel(find.statusLabel)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: 340)
        .background(Color.bgInput)
        .clipShape(.rect(cornerRadius: Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control)
                .stroke(isFieldFocused ? Color.borderPrimary : Color.borderInput, lineWidth: 1)
        )
    }

    // MARK: - Buttons

    private func stepButton(
        systemImage: String,
        label: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(find.canStep ? Color.textSecondary : Color.textMuted)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!find.canStep)
        .help(help)
        .accessibilityLabel(label)
    }

    private var closeButton: some View {
        Button {
            close()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close find (Esc)")
        .accessibilityLabel("Close find")
    }

    // MARK: - Actions

    /// Return steps forward; with Shift held, back.
    private func submit() {
        #if os(macOS)
        let backwards = NSEvent.modifierFlags.contains(.shift)
        #else
        let backwards = false
        #endif
        if backwards {
            find.findPrevious()
        } else {
            find.findNext()
        }
        // Stepping is a repeated action; the keyboard stays in the field.
        isFieldFocused = true
    }

    private func close() {
        withAnimation(Self.revealAnimation(reduceMotion: reduceMotion)) {
            find.dismiss()
        }
    }

    private func focusField() {
        // A turn later, as the search overlay does: focus requested in the
        // same pass that mounts the field does not take.
        Task { @MainActor in
            await Task.yield()
            isFieldFocused = true
        }
    }
}
