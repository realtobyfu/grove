import Foundation

/// Global appearance settings stored in UserDefaults.
struct AppearanceSettings: Sendable {
    private static var defaults: UserDefaults { UserDefaults.standard }

    private enum Key: String {
        case monochromeCoverImages = "grove.appearance.monochromeCoverImages"
        case theme = "grove.appearance.theme"
    }

    /// The look of the app. Read through `ThemeStore`, which is what views
    /// observe; this is only where the choice is kept between launches.
    static var theme: GroveTheme {
        get { defaults.string(forKey: Key.theme.rawValue).flatMap(GroveTheme.init(rawValue:)) ?? .grove }
        set { defaults.set(newValue.rawValue, forKey: Key.theme.rawValue) }
    }

    /// When true, cover images are rendered in black and white.
    static var monochromeCoverImages: Bool {
        get { defaults.object(forKey: Key.monochromeCoverImages.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.monochromeCoverImages.rawValue) }
    }
}
