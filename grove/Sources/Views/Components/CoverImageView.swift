import SwiftUI

/// Reusable cover image component with clipped banner rendering,
/// optional desaturation, video play overlay, and a subtle bottom gradient.
struct CoverImageView: View {
    let imageData: Data
    var height: CGFloat = 120
    var showPlayOverlay: Bool = false
    var cornerRadius: CGFloat = 4
    var isDesaturated: Bool? = nil
    var contentMode: ContentMode = .fill
    @AppStorage("grove.appearance.monochromeCoverImages")
    private var monochromeCoverImages = true

    private var platformImage: Image? {
        #if os(macOS)
        guard let nsImage = NSImage(data: imageData) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(data: imageData) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }

    var body: some View {
        if let image = platformImage {
            image
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: contentMode)
                .saturation((isDesaturated ?? monochromeCoverImages) ? 0.0 : 1.0)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Color.bgInput)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.18), Color.clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: height * 0.5)
                }
                .overlay {
                    if showPlayOverlay {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color.white.opacity(0.95))
                            .shadow(radius: 2)
                    }
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
