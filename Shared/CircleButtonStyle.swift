// CircleButtonStyle: start, stop, continue, and pause buttons
// (spec_timer_window.md §2).

import SwiftUI

/// A filled circle with a white glyph about 36% of its diameter; large ones
/// carry a soft halo of their color.
struct CircleButtonStyle: ButtonStyle {
    var color: Color
    var diameter: CGFloat
    var halo = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.36, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(color.opacity(configuration.isPressed ? 0.8 : 1)))
            .background(Circle().fill(color.opacity(halo ? 0.25 : 0)).padding(-4))
            .contentShape(Circle())
    }
}

extension Color {
    static let startGreen = Color(red: 0.30, green: 0.69, blue: 0.43)
    static let stopRed = Color(red: 0.87, green: 0.42, blue: 0.36)
}
