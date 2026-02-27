import SwiftUI

/// Floating "+" button positioned above the tab bar safe area.
/// Tapping presents CaptureSheetView as a sheet.
/// Intended to overlay Home, Inbox, and Library tabs on iPhone.
struct FloatingCaptureButton: View {
    @State private var showCaptureSheet = false

    var body: some View {
        Button {
            showCaptureSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.textInverse)
                .frame(width: 56, height: 56)
                .background(Color.textPrimary)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .accessibilityLabel("Capture")
        .accessibilityHint("Add a new link or note")
        .keyboardShortcut("n", modifiers: .command)
        .sheet(isPresented: $showCaptureSheet) {
            CaptureSheetView()
        }
    }
}
