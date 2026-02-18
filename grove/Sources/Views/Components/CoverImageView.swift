import SwiftUI

/// Reusable cover image component. Renders image data as a grayscale, clipped banner
/// with an optional play overlay for videos and a subtle bottom gradient.
struct CoverImageView: View {
    let imageData: Data
    var height: CGFloat = 120
    var showPlayOverlay: Bool = false
    var cornerRadius: CGFloat = 4

    var body: some View {
        if let nsImage = NSImage(data: imageData) {
            ZStack(alignment: .center) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                    .saturation(0.0)

                // Subtle bottom gradient overlay
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [Color.black.opacity(0.12), Color.clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: height * 0.4)
                }
                .frame(height: height)

                if showPlayOverlay {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.white.opacity(0.9))
                        .shadow(radius: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
