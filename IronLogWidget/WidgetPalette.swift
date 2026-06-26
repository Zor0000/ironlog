import SwiftUI

/// Self-contained palette for the widget extension so it doesn't have to pull
/// in the app's `Theme`. Brand values mirror `IronLog/Theme.swift`; the neutral
/// surfaces use white-on-dark opacities so they layer cleanly on the Live
/// Activity's dark background tint in both light and dark system appearance.
enum WidgetPalette {
    static let accent = Color(red: 0.831, green: 1.0, blue: 0.29)
    static let success = Color(red: 0.40, green: 0.92, blue: 0.58)
    static let text = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let muted = Color(red: 0.62, green: 0.62, blue: 0.64)
    static let surfaceDeep = Color(red: 0.07, green: 0.07, blue: 0.08)

    /// Raised tile behind each stepper.
    static let tile = Color.white.opacity(0.05)
    static let tileStroke = Color.white.opacity(0.09)
    /// The ± step buttons sit one level above the tile.
    static let stepButton = Color.white.opacity(0.13)
    /// Secondary (non-primary) action button, e.g. Next / Undo.
    static let secondaryButton = Color.white.opacity(0.11)
    /// Empty / upcoming set pip.
    static let pip = Color.white.opacity(0.16)
}
