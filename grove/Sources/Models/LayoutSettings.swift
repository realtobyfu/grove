import Foundation
import CoreGraphics

/// Global pane width settings stored in UserDefaults.
struct LayoutSettings: Sendable {
    enum PaneWidthKey: String, CaseIterable, Sendable {
        case contentWrite = "grove.layout.width.contentWrite"
        case contentChat = "grove.layout.width.contentChat"
        case contentInspector = "grove.layout.width.contentInspector"
        case homePrompt = "grove.layout.width.homePrompt"
        case boardPrompt = "grove.layout.width.boardPrompt"
        case readerReflections = "grove.layout.width.readerReflections"
        case mobileReaderSidePanel = "grove.layout.width.mobileReaderSidePanel"
    }

    private static var defaults: UserDefaults { UserDefaults.standard }

    static func width(for key: PaneWidthKey) -> CGFloat? {
        guard let storedWidth = defaults.object(forKey: key.rawValue) as? Double else {
            return nil
        }
        return CGFloat(storedWidth)
    }

    static func setWidth(_ width: CGFloat, for key: PaneWidthKey) {
        defaults.set(Double(width), forKey: key.rawValue)
    }
}
