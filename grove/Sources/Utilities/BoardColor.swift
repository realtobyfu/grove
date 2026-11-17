import SwiftUI

/// Board icon colours — the one place the app uses colour. Everything else
/// stays ink on paper; a board's icon may carry a tint its owner picked, so
/// boards can be told apart at a glance in the sidebar.
///
/// `Board.color` stores a bare six-digit hex ("34C759"), or `nil` for plain ink.
enum BoardColor {
    struct Option: Identifiable, Hashable {
        let hex: String
        let name: String

        var id: String { hex }
    }

    /// The palette offered in the board editor. Hex values match what builds
    /// before the monochrome redesign stored, so boards coloured back then
    /// show up as one of these swatches.
    static let options: [Option] = [
        Option(hex: "007AFF", name: "Blue"),
        Option(hex: "34C759", name: "Green"),
        Option(hex: "FF3B30", name: "Red"),
        Option(hex: "FF9500", name: "Orange"),
        Option(hex: "AF52DE", name: "Purple"),
        Option(hex: "FF2D55", name: "Pink"),
        Option(hex: "5856D6", name: "Indigo"),
        Option(hex: "00C7BE", name: "Teal"),
        Option(hex: "A2845E", name: "Brown"),
        Option(hex: "8E8E93", name: "Gray"),
        Option(hex: "FFD60A", name: "Yellow"),
        Option(hex: "64D2FF", name: "Sky"),
    ]

    /// A stored colour as bare uppercase hex, or `nil` when it isn't a colour.
    /// Accepts the "#RRGGBB" spelling too, since imported boards used it.
    static func normalized(_ stored: String?) -> String? {
        guard let stored else { return nil }
        let hex = stored
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }

    /// The colour for a stored value, or `nil` when it should draw in ink.
    static func color(for stored: String?) -> Color? {
        guard let hex = normalized(stored), let value = UInt32(hex, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Board {
    /// The tint chosen for this board's icon, or `nil` for plain ink.
    var iconTint: Color? {
        BoardColor.color(for: color)
    }
}
