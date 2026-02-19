import Foundation

/// Global appearance settings stored in UserDefaults.
struct AppearanceSettings: Sendable {
    private static var defaults: UserDefaults { UserDefaults.standard }

    private enum Key: String {
        case monochromeCoverImages = "grove.appearance.monochromeCoverImages"
    }

    /// When true, cover images are rendered in black and white.
    static var monochromeCoverImages: Bool {
        get { defaults.object(forKey: Key.monochromeCoverImages.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.monochromeCoverImages.rawValue) }
    }
}
