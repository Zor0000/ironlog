import SwiftUI

/// Self-contained palette for the widget extension so it doesn't have to pull
/// in the app's `Theme`. Brand values mirror `IronLog/Theme.swift`.
///
/// The card itself is left untinted so iOS renders its native blurred-material
/// Live Activity background — real wallpaper blur, which a widget can't draw
/// itself. Every surface on top of it is therefore a translucent white wash
/// plus a hairline stroke, so the blur reads through instead of being covered.
enum WidgetPalette {
    static let accent = Color(red: 0.831, green: 1.0, blue: 0.29)
    static let success = Color(red: 0.55, green: 0.97, blue: 0.72)
    static let text = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let muted = Color.white.opacity(0.6)

    /// Raised tile behind each stepper.
    static let tile = Color.white.opacity(0.06)
    static let tileStroke = Color.white.opacity(0.10)
    /// The ± step buttons sit one level above the tile.
    static let stepButton = Color.white.opacity(0.08)
    static let stepStroke = Color.white.opacity(0.14)
    /// Secondary (non-primary) action button, e.g. Next / Undo.
    static let secondaryButton = Color.white.opacity(0.10)
    /// Empty / upcoming set pip.
    static let pip = Color.white.opacity(0.18)
}
