import SwiftUI

/// Shown instead of the app when the library could not open. Showing an empty
/// library here would look like the data was gone, and anything added to it
/// would be lost.
struct LibraryUnavailableView: View {
    let reason: String

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.groveTitleLarge)
                .foregroundStyle(Color.textSecondary)
            Text("Grove couldn’t open your library")
                .font(.groveTitleLarge)
                .foregroundStyle(Color.textPrimary)
            Text("Nothing in it has been changed. Quit Grove and open it again to retry.")
                .font(.groveBody)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Text(reason)
                .font(.groveMeta)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }
}
