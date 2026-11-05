// Hatch: the diagonal hatch of Reports' repeated project colors, the
// Calendar's knowledge blocks and the time after now, and Activity's open
// block (spec_reports.md §4, spec_calendar.md §1.2, §3.1, spec_activity.md §1.5).

import SwiftUI

/// A tiled fill of diagonal stripes over a background.
enum Hatch {
    /// The tile's side; the stripes repeat at this distance.
    static let spacing: CGFloat = 6

    /// Stripes of `stripe` over `background`, usable as any `ShapeStyle`
    /// (shapes and chart marks).
    static func paint(_ stripe: Color, on background: Color = .clear, lineWidth: CGFloat = 1.5) -> ImagePaint {
        let side = spacing
        let image = Image(size: CGSize(width: side, height: side)) { context in
            context.fill(Path(CGRect(x: 0, y: 0, width: side, height: side)), with: .color(background))
            var path = Path()
            // The diagonal and the two corner pieces make the tiles seamless.
            for shift in [-side, 0, side] {
                path.move(to: CGPoint(x: shift - 1, y: side + 1))
                path.addLine(to: CGPoint(x: shift + side + 1, y: -1))
            }
            context.stroke(path, with: .color(stripe), lineWidth: lineWidth)
        }
        return ImagePaint(image: image)
    }
}
