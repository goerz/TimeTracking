// The text color of a Calendar card on its area color
// (spec_calendar.md §2.1; spec_projects.md §4.4).

import SwiftUI
import TimeTrackingCore

/// The text color on an area color (§4.4 of the Projects spec).
func cardTextColor(_ hex: String?) -> Color {
    guard let hex, let color = try? AreaColor(hex) else {
        return .primary
    }
    return color.textColor == .black ? .black : .white
}
