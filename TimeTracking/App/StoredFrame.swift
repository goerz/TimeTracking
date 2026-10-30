// StoredFrame: a window frame in the device settings (spec_timer_window.md §1.1).

import CoreGraphics
import Foundation

/// A window frame as stored in the device settings.
nonisolated struct StoredFrame: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.width
        self.height = rect.height
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
