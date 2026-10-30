// CircleButtonStyle: start, stop, continue, and discard buttons
// (spec_design.md §7).

import SwiftUI

/// A filled circle with a glyph at 40% of its diameter: white on a color
/// (start, stop, continue), or secondary on a quaternary fill (discard).
struct CircleButtonStyle: ButtonStyle {
    var fill: AnyShapeStyle
    var glyph: AnyShapeStyle
    var diameter: CGFloat

    /// A white glyph on `color`.
    init(color: Color, diameter: CGFloat) {
        self.fill = AnyShapeStyle(color)
        self.glyph = AnyShapeStyle(.white)
        self.diameter = diameter
    }

    /// The secondary circle of the discard button.
    static func secondary(diameter: CGFloat) -> Self {
        var style = Self(color: .clear, diameter: diameter)
        style.fill = AnyShapeStyle(.quaternary)
        style.glyph = AnyShapeStyle(.secondary)
        return style
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: diameter * 0.4, weight: .semibold))
            .foregroundStyle(glyph)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(fill).opacity(configuration.isPressed ? 0.75 : 1))
            .contentShape(Circle())
    }
}

extension Color {
    // Kept until every surface uses `startTint` and `stopTint`.
    static let startGreen = Color(red: 0.30, green: 0.69, blue: 0.43)
    static let stopRed = Color(red: 0.87, green: 0.42, blue: 0.36)
}
