// Color+Hex: area colors from their `#RRGGBB` text (spec_design.md §6,
// spec_planner_projects.md §4.4).

import SwiftUI
import TimeTrackingCore

extension Color {
    /// The color of an `#RRGGBB` value, parsed by the library's
    /// `AreaColor`; gray for a malformed one.
    init(hex: String) {
        let color = (try? AreaColor(hex)) ?? AreaColor(red: UInt8(0x80), green: 0x80, blue: 0x80)
        self.init(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }
}
