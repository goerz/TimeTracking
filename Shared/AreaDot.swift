// AreaDot: an area color as a dot or swatch (spec_planner_projects.md §4.4,
// spec_design.md §7).

import SwiftUI
import TimeTrackingCore

extension Color {
    /// The color of an `#RRGGBB` value; gray for a malformed one.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(digits, radix: 16) ?? 0x808080
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// An 8 pt solid circle in the area color, or a hollow one (1 pt secondary
/// stroke) for "No project" (spec_design.md §7).
struct AreaDot: View {
    var color: String?
    var size: CGFloat = 8

    var body: some View {
        if let color {
            Circle().fill(Color(hex: color)).frame(width: size, height: size)
        } else {
            Circle().strokeBorder(.secondary, lineWidth: 1).frame(width: size, height: size)
        }
    }
}

/// A 16 pt rounded square in the area color (popups, sheets).
struct AreaSwatch: View {
    var color: String

    var body: some View {
        RoundedRectangle(cornerRadius: 4).fill(Color(hex: color)).frame(width: 16, height: 16)
    }
}
